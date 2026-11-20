import Foundation
import CoreGraphics
import MetalPetal

/// Keeps skin smoothing to skin only (2026-11-20).
///
/// The smoothing filter works on the whole picture, so beard, eyebrows, hairline and whatever
/// is behind the person go soft too. On an iPhone 16 Pro Max that read as "you can tell
/// smoothing is on"; the iPhone 18 Pro Max's sharper selfie camera hides it, and the user is
/// happy with the look there, so that phone keeps the whole-picture smoothing.
///
/// How: every dot of the unsmoothed picture is looked up in a colour table that says how
/// skin-coloured it is (0 to 1). That map is softened a little so there are no hard edges, and
/// the smoothed picture is kept only where the map says skin. Nothing follows the face from
/// picture to picture, so it cannot lag behind a moving face.
enum SkinOnlySmoothing {
    /// On for iPhones older than the iPhone 18 line (model numbers below "iPhone19,…").
    /// The simulator and iPads report other names and keep the whole-picture smoothing.
    static let isOn: Bool = {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        guard model.hasPrefix("iPhone"),
              let line = Int(model.dropFirst("iPhone".count).prefix { $0.isNumber }) else { return false }
        return line < 19
    }()

    /// How soft the edge of the skin map is, in dots, on a picture 1080 dots across its short side
    private static let edgeSoftness: Float = 6

    /// The smoothed picture where the original is skin-coloured, the original everywhere else
    static func kept(toSkin smoothed: MTIImage, original: MTIImage) -> MTIImage {
        guard let table else { return smoothed }
        let lookup = MTIColorLookupFilter()
        lookup.inputImage = original
        lookup.inputColorLookupTable = table
        guard let skinMap = lookup.outputImage else { return smoothed }

        let blur = MTIMPSGaussianBlurFilter()
        blur.inputImage = skinMap
        blur.radius = edgeSoftness * Float(min(original.size.width, original.size.height)) / 1080
        guard let softMap = blur.outputImage else { return smoothed }

        let blend = MTIBlendWithMaskFilter()
        blend.inputImage = smoothed
        blend.inputBackgroundImage = original
        blend.inputMask = MTIMask(content: softMap, component: .red, mode: .normal)
        return blend.outputImage ?? smoothed
    }

    /// The colour table: 64 steps per colour, laid out as 8 x 8 tiles of 64 x 64 (blue picks the
    /// tile, red runs across it, green down it). Each entry is how skin-coloured that colour is,
    /// from where it sits in brightness and in the two colour-difference values (Cb, Cr) that
    /// skin of every tone shares. The edges of the range are ramps, not steps.
    private static let table: MTIImage? = {
        func ramp(_ x: Float, _ low: Float, _ high: Float) -> Float {
            let t = max(0, min(1, (x - low) / (high - low)))
            return t * t * (3 - 2 * t)
        }
        let steps = 64, tiles = 8, side = 512
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        for blue in 0..<steps {
            for green in 0..<steps {
                for red in 0..<steps {
                    let r = Float(red) / Float(steps - 1) * 255
                    let g = Float(green) / Float(steps - 1) * 255
                    let b = Float(blue) / Float(steps - 1) * 255
                    let brightness = 0.299 * r + 0.587 * g + 0.114 * b
                    let cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b
                    let cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b
                    let skin = ramp(cr, 136, 146) * (1 - ramp(cr, 175, 185))
                        * ramp(cb, 75, 85) * (1 - ramp(cb, 120, 128))
                        * ramp(brightness, 40, 75)
                    let x = (blue % tiles) * steps + red
                    let y = (blue / tiles) * steps + green
                    let value = UInt8((skin * 255).rounded())
                    let at = (y * side + x) * 4
                    bytes[at] = value
                    bytes[at + 1] = value
                    bytes[at + 2] = value
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: side * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { return nil }
        // The numbers are used as they are: no colour conversion on the way in
        return MTIImage(cgImage: image, options: [.SRGB: false], isOpaque: true)
    }()
}
