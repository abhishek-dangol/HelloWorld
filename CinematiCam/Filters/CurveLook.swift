import CoreImage
import CoreGraphics

/// A colour look built as a lookup table (a 3D colour cube) so it can bend tones the way
/// photo filters do: an S-shaped contrast curve, a different tint in the dark, middle and
/// bright areas, faded blacks, and colour-only-where-it-matters saturation.
/// Colours use the screen scale: 0 is black, 1 is white. The table is built once per look.
struct CurveLook: Filter {
    let name: String
    /// Positive brightens the middle tones without blowing out whites (about one stop per 1.0).
    var brightness: Double = 0
    /// -1...1. Positive is an S-curve (punchier), negative flattens.
    var contrast: Double = 0
    var saturation: Double = 1
    /// Black-and-white.
    var mono = false
    /// The colour pure black becomes (lifted = faded look) and the colour pure white becomes.
    var shadows: [Double] = [0, 0, 0]
    var highlights: [Double] = [1, 1, 1]
    /// Per-channel middle-tone shift: positive red = warmer mids, positive blue = cooler mids.
    var midtones: [Double] = [0, 0, 0]
    /// Colour added only to the dark areas / only to the bright areas (teal-and-orange style).
    var shadowTint: [Double] = [0, 0, 0]
    var highlightTint: [Double] = [0, 0, 0]
    var vignette: Double = 0
    /// Soft glow around bright areas; 0 is off.
    var bloom: Double = 0

    private let cubeData: Data
    private static let size = 32

    init(name: String, brightness: Double = 0, contrast: Double = 0, saturation: Double = 1,
         mono: Bool = false, shadows: [Double] = [0, 0, 0], highlights: [Double] = [1, 1, 1],
         midtones: [Double] = [0, 0, 0], shadowTint: [Double] = [0, 0, 0],
         highlightTint: [Double] = [0, 0, 0], vignette: Double = 0, bloom: Double = 0) {
        self.name = name
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.mono = mono
        self.shadows = shadows
        self.highlights = highlights
        self.midtones = midtones
        self.shadowTint = shadowTint
        self.highlightTint = highlightTint
        self.vignette = vignette
        self.bloom = bloom
        self.cubeData = Self.buildCube(brightness: brightness, contrast: contrast, saturation: saturation,
                                       mono: mono, shadows: shadows, highlights: highlights,
                                       midtones: midtones, shadowTint: shadowTint, highlightTint: highlightTint)
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }

    private static func buildCube(brightness: Double, contrast: Double, saturation: Double, mono: Bool,
                                  shadows: [Double], highlights: [Double], midtones: [Double],
                                  shadowTint: [Double], highlightTint: [Double]) -> Data {
        let n = size
        var cube = [Float](repeating: 1, count: n * n * n * 4)
        let brightExponent = pow(2.0, -brightness)
        var offset = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    var c = [Double(r), Double(g), Double(b)].map { $0 / Double(n - 1) }
                    c = c.map { pow($0, brightExponent) }
                    let luma = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
                    if mono {
                        c = [luma, luma, luma]
                    } else {
                        c = c.map { luma + ($0 - luma) * saturation }
                    }
                    for i in 0..<3 {
                        var v = clamp(c[i])
                        v = pow(v, pow(2.0, -midtones[i]))
                        if contrast >= 0 {
                            let s = v * v * (3 - 2 * v)
                            v += (s - v) * contrast
                        } else {
                            v = 0.5 + (v - 0.5) * (1 + contrast)
                        }
                        c[i] = shadows[i] + v * (highlights[i] - shadows[i])
                    }
                    let l = clamp(0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2])
                    let dark = (1 - l) * (1 - l)
                    let bright = l * l
                    for i in 0..<3 {
                        c[i] = clamp(c[i] + shadowTint[i] * dark + highlightTint[i] * bright)
                    }
                    cube[offset] = Float(c[0])
                    cube[offset + 1] = Float(c[1])
                    cube[offset + 2] = Float(c[2])
                    offset += 4
                }
            }
        }
        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    func apply(to image: CIImage) -> CIImage {
        let extent = image.extent
        var output = image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": Self.size,
            "inputCubeData": cubeData,
            "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!
        ])
        if bloom > 0 {
            output = output.applyingFilter("CIBloom", parameters: [
                kCIInputRadiusKey: extent.width * 0.012,
                kCIInputIntensityKey: bloom
            ])
        }
        if vignette > 0 {
            output = output.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: vignette,
                kCIInputRadiusKey: 1.6
            ])
        }
        return output.cropped(to: extent)
    }
}
