import CoreImage
import Foundation

/// A colour look graded the way photo apps grade: in a colour space where lightness, colour
/// strength and hue can be changed separately (OKLab), baked into a lookup table (a 3D colour
/// cube) so it runs on the camera feed at full speed.
///
/// What makes it look better than plain RGB curves:
/// - Skin tones are protected: saturation, vibrance and colour shifts touch faces much less,
///   so people do not turn orange, grey or green.
/// - Contrast bends around middle grey with a soft toe and shoulder, so whites never clip and
///   blacks never crush.
/// - Colours that would fall outside what the screen can show are pulled in by lowering their
///   strength, not by clipping, so bright reds and blues keep their shape.
/// - Optional fine film grain that changes every frame.
///
/// Colour amounts are in OKLab units (0.01 is subtle, 0.04 is strong). Hues are in degrees:
/// red 25, orange 55, yellow 100, green 140, teal 195, blue 260, purple 300, pink 340.
final class GradeLook: Filter {
    /// Changes the strength, hue or lightness of one family of colours (for example greens).
    struct Band {
        var hue: Double
        /// How wide the colour family is, in degrees either side
        var width: Double = 30
        var hueShift: Double = 0
        var chroma: Double = 1
        var light: Double = 0
    }

    /// A colour tint: which hue, how strong
    struct Tint {
        var hue: Double
        var amount: Double
    }

    let name: String
    /// About one stop per 1.0, on the middle tones; whites and blacks stay put.
    var brightness: Double = 0
    /// -1...1: positive deepens the S-curve around middle grey.
    var contrast: Double = 0
    /// Pulls the darkest greys down to true black, like Crisp does; most phone pictures have
    /// greyish shadows. Applied before `fade`, so a faded look gets an even, chosen black.
    var blacks: Double = 0.2
    /// Lifts pure black toward grey (the faded look). 0.05 is a light matte.
    var fade: Double = 0
    /// Softens the brightest whites toward grey. 0.05 is a light roll-off.
    var softWhites: Double = 0
    var saturation: Double = 1
    /// Boosts the dull colours more than the strong ones.
    var vibrance: Double = 0
    /// Warmer (+) or cooler (-) overall, like a white-balance slider.
    var warmth: Double = 0
    /// Toward magenta (+) or green (-).
    var tint: Double = 0
    var shadowTint: Tint?
    var midTint: Tint?
    var highlightTint: Tint?
    var bands: [Band] = []
    /// 0 lets skin take every colour change, 1 shields it fully.
    var skinProtect: Double = 0.7
    /// Black-and-white with this red/green/blue mix (like a coloured lens filter on film).
    var mono: [Double]?
    /// Fine grain, 0.03 is light film grain.
    var grain: Double = 0
    var vignette: Double = 0
    var bloom: Double = 0
    /// A red-orange glow around the brightest spots, like night film (CineStill); 0 is off.
    var halation: Double = 0

    init(name: String, brightness: Double = 0, contrast: Double = 0, blacks: Double = 0.2, fade: Double = 0,
         softWhites: Double = 0, saturation: Double = 1, vibrance: Double = 0, warmth: Double = 0,
         tint: Double = 0, shadowTint: Tint? = nil, midTint: Tint? = nil, highlightTint: Tint? = nil,
         bands: [Band] = [], skinProtect: Double = 0.7, mono: [Double]? = nil, grain: Double = 0,
         vignette: Double = 0, bloom: Double = 0, halation: Double = 0) {
        self.name = name
        self.brightness = brightness
        self.contrast = contrast
        self.blacks = blacks
        self.fade = fade
        self.softWhites = softWhites
        self.saturation = saturation
        self.vibrance = vibrance
        self.warmth = warmth
        self.tint = tint
        self.shadowTint = shadowTint
        self.midTint = midTint
        self.highlightTint = highlightTint
        self.bands = bands
        self.skinProtect = skinProtect
        self.mono = mono
        self.grain = grain
        self.vignette = vignette
        self.bloom = bloom
        self.halation = halation
    }

    // MARK: - The cube, built the first time the look is used

    private static let size = 32
    private let cubeLock = NSLock()
    private var builtCube: Data?
    private var cube: Data {
        cubeLock.lock()
        defer { cubeLock.unlock() }
        if let builtCube { return builtCube }
        let made = buildCube()
        builtCube = made
        return made
    }

    /// Builds the lookup table now (about 20-50 ms), so the first use does not stutter
    func prepare() { _ = cube }

    func apply(to image: CIImage) -> CIImage {
        let extent = image.extent
        var output = image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": Self.size,
            "inputCubeData": cube,
            "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!
        ])
        if bloom > 0 {
            // Edge pixels are repeated outward first, or the glow pulls dark into the corners
            output = output.clampedToExtent().applyingFilter("CIBloom", parameters: [
                kCIInputRadiusKey: extent.width * 0.012,
                kCIInputIntensityKey: bloom
            ]).cropped(to: extent)
        }
        if halation > 0 {
            output = addHalation(to: output, extent: extent)
        }
        if vignette > 0 {
            output = output.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: vignette,
                kCIInputRadiusKey: 1.6
            ])
        }
        if grain > 0 {
            output = addGrain(to: output.cropped(to: extent), extent: extent)
        }
        return output.cropped(to: extent)
    }

    /// Keeps only the brightest spots, tints them red-orange, blurs them wide and adds them back
    private func addHalation(to image: CIImage, extent: CGRect) -> CIImage {
        let k = CGFloat(1.5 * halation), threshold: CGFloat = 0.85
        let colour: [CGFloat] = [1, 0.3, 0.08]
        func row(_ c: CGFloat) -> CIVector { CIVector(x: 0.3 * k * c, y: 0.59 * k * c, z: 0.11 * k * c, w: 0) }
        let glow = image
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": row(colour[0]), "inputGVector": row(colour[1]), "inputBVector": row(colour[2]),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: -threshold * k * colour[0], y: -threshold * k * colour[1],
                                            z: -threshold * k * colour[2], w: 0)
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: extent.width * 0.02])
            .cropped(to: extent)
        return glow.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: extent)
    }

    /// A small square of grey noise made once and repeated across the picture; cheaper on
    /// every frame than making fresh noise for the whole picture
    private static let noiseTile: CIImage = {
        let side = 256
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<(side * side) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = UInt8(truncatingIfNeeded: seed >> 56)
            bytes[i * 4] = v; bytes[i * 4 + 1] = v; bytes[i * 4 + 2] = v
        }
        return CIImage(bitmapData: Data(bytes), bytesPerRow: side * 4, size: CGSize(width: side, height: side),
                       format: .RGBA8, colorSpace: nil)
    }()

    /// Grey noise around middle grey, soft-light blended so it shows in the middle tones
    /// like film grain and leaves black and white alone. Moves every frame.
    private func addGrain(to image: CIImage, extent: CGRect) -> CIImage {
        // Grain about 1/1500 of the picture's long side, so it looks the same at any size
        let grainSize = max(1, (max(extent.width, extent.height) / 1500).rounded())
        let amount = CGFloat(grain) * 2
        let noise = Self.noiseTile
            .transformed(by: CGAffineTransform(scaleX: grainSize, y: grainSize))
            .applyingFilter("CIAffineTile")
            .transformed(by: CGAffineTransform(translationX: CGFloat(Int.random(in: 0..<256)) * grainSize,
                                               y: CGFloat(Int.random(in: 0..<256)) * grainSize))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0.5 - amount / 2, y: 0.5 - amount / 2, z: 0.5 - amount / 2, w: 1)
            ])
            .cropped(to: extent)
        return noise.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
    }

    // MARK: - Colour maths

    private func buildCube() -> Data {
        let n = Self.size
        var data = [Float](repeating: 1, count: n * n * n * 4)
        var offset = 0
        for bi in 0..<n {
            for gi in 0..<n {
                for ri in 0..<n {
                    let input = (Double(ri), Double(gi), Double(bi))
                    let out = grade(r: input.0 / Double(n - 1), g: input.1 / Double(n - 1), b: input.2 / Double(n - 1))
                    data[offset] = Float(out.0)
                    data[offset + 1] = Float(out.1)
                    data[offset + 2] = Float(out.2)
                    offset += 4
                }
            }
        }
        return data.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// One screen colour (0...1 each) in, the graded screen colour out
    func grade(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        var lin = (Self.toLinear(r), Self.toLinear(g), Self.toLinear(b))
        if let mix = mono {
            let y = max(0, mix[0] * lin.0 + mix[1] * lin.1 + mix[2] * lin.2)
            lin = (y, y, y)
        }
        var (L, A, B) = Self.oklab(lin)
        var chroma = (A * A + B * B).squareRoot()
        var hue = atan2(B, A) * 180 / .pi
        if hue < 0 { hue += 360 }

        // How much this colour looks like skin: orange hues, moderate strength, not too dark
        let skin = skinProtect * Self.bell(Self.hueDistance(hue, 62), 30)
            * Self.smooth(0.015, 0.04, chroma) * (1 - Self.smooth(0.17, 0.24, chroma))
            * Self.smooth(0.25, 0.45, L)

        // How much this colour looks like sky or water: blue hues, even when pale
        let sky = Self.bell(Self.hueDistance(hue, 245), 40) * Self.smooth(0.003, 0.02, chroma) * Self.smooth(0.45, 0.7, L)

        // Lightness: brightness, S-curve, faded blacks, soft whites
        if brightness != 0 { L = pow(max(L, 0), pow(2, -brightness * 0.6)) }
        if contrast != 0 { L = Self.sCurve(L, contrast) }
        if blacks != 0 { L = max(0, L - blacks * pow(1 - min(max(L, 0), 1), 6)) }
        if fade != 0 { L += fade * pow(1 - L, 3) }
        if softWhites != 0 { L -= softWhites * pow(L, 4) }

        // Colour strength
        let original = chroma
        if vibrance != 0 { chroma *= 1 + vibrance * max(0, 1 - chroma / 0.22) }
        chroma *= saturation
        for band in bands {
            let w = Self.bell(Self.hueDistance(hue, band.hue), band.width) * (1 - skin)
            guard w > 0.001 else { continue }
            hue += band.hueShift * w
            chroma *= 1 + (band.chroma - 1) * w
            L += band.light * w * Self.smooth(0.0, 0.05, original)
        }
        // Skin keeps most of its own colour strength
        chroma = original + (chroma - original) * (1 - skin)

        A = chroma * cos(hue * .pi / 180)
        B = chroma * sin(hue * .pi / 180)

        // Tints: whole picture (white balance), then dark / middle / bright areas
        let l = min(max(L, 0), 1)
        // Faces take about half of any tint, so they stay believable
        // Faces take a third of any tint, and skies keep their blue under any tint that is not
        // itself blue, so a sky never turns cream, lavender or grey
        let onSkin = 1 - 0.65 * skin
        // Near-white areas (clouds, white clothes, hazy sky) stay mostly clean
        let clean = 1 - 0.6 * Self.smooth(0.78, 0.97, l) * (1 - Self.smooth(0.02, 0.06, original))
        func onSky(_ hue: Double) -> Double {
            (1 - 0.85 * sky * Self.smooth(25, 70, Self.hueDistance(hue, 245))) * clean
        }
        A += 0.02 * tint * l * onSkin * onSky(tint > 0 ? 0 : 180)
        B += 0.03 * warmth * l * (warmth < 0 ? 1 - 0.9 * skin : onSkin) * onSky(warmth > 0 ? 90 : 270)
        if let t = shadowTint { Self.add(t, (1 - l) * (1 - l) * onSkin * onSky(t.hue), &A, &B) }
        if let t = midTint { Self.add(t, 4 * l * (1 - l) * onSkin * onSky(t.hue), &A, &B) }
        if let t = highlightTint { Self.add(t, l * l * onSkin * onSky(t.hue), &A, &B) }

        let fitted = Self.fitToScreen(L: min(max(L, 0), 1), A: A, B: B)
        return (Self.toScreen(fitted.0), Self.toScreen(fitted.1), Self.toScreen(fitted.2))
    }

    private static func add(_ t: Tint, _ weight: Double, _ a: inout Double, _ b: inout Double) {
        a += t.amount * weight * cos(t.hue * .pi / 180)
        b += t.amount * weight * sin(t.hue * .pi / 180)
    }

    /// Contrast around the middle (OKLab 0.5) that never clips: a power curve each side
    private static func sCurve(_ x: Double, _ k: Double) -> Double {
        let p = 0.5, e = 1 + k
        let v = min(max(x, 0), 1)
        return v < p ? p * pow(v / p, e) : 1 - (1 - p) * pow((1 - v) / (1 - p), e)
    }

    /// Keeps lightness and hue, lowers colour strength until the colour fits the screen
    private static func fitToScreen(L: Double, A: Double, B: Double) -> (Double, Double, Double) {
        var rgb = linear(L, A, B)
        func fits(_ c: (Double, Double, Double)) -> Bool {
            min(c.0, c.1, c.2) >= -0.0005 && max(c.0, c.1, c.2) <= 1.0005
        }
        if fits(rgb) { return clamp(rgb) }
        var low = 0.0, high = 1.0
        for _ in 0..<10 {
            let mid = (low + high) / 2
            if fits(linear(L, A * mid, B * mid)) { low = mid } else { high = mid }
        }
        rgb = linear(L, A * low, B * low)
        return clamp(rgb)
    }

    private static func clamp(_ c: (Double, Double, Double)) -> (Double, Double, Double) {
        (min(max(c.0, 0), 1), min(max(c.1, 0), 1), min(max(c.2, 0), 1))
    }

    static func bell(_ distance: Double, _ width: Double) -> Double {
        exp(-(distance * distance) / (2 * width * width / 2.3))
    }

    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    static func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func toLinear(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func toScreen(_ v: Double) -> Double {
        v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    /// Linear sRGB to OKLab (Björn Ottosson, 2020, public domain)
    static func oklab(_ c: (Double, Double, Double)) -> (Double, Double, Double) {
        let l = cbrt(0.4122214708 * c.0 + 0.5363325363 * c.1 + 0.0514459929 * c.2)
        let m = cbrt(0.2119034982 * c.0 + 0.6806995451 * c.1 + 0.1073969566 * c.2)
        let s = cbrt(0.0883024619 * c.0 + 0.2817188376 * c.1 + 0.6299787005 * c.2)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    static func linear(_ L: Double, _ a: Double, _ b: Double) -> (Double, Double, Double) {
        let l = pow(L + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(L - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(L - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }
}
