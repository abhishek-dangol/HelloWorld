import CoreImage
import Foundation

/// A colour look described by a few numbers, so adding a look is one entry in `FilterLibrary`.
/// Colours use the same scale as the screen: 0 is black, 1 is white.
struct LookFilter: Filter {
    let name: String
    /// Brightness in camera stops; 0 leaves it alone.
    var exposure: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    /// The colour pure black becomes: lifts the dark areas (a faded look) and tints them.
    var shadows: [CGFloat] = [0, 0, 0]
    /// The colour pure white becomes: tints the bright areas.
    var highlights: [CGFloat] = [1, 1, 1]
    /// Darkens the corners; 0 is off.
    var vignette: Double = 0

    func apply(to image: CIImage) -> CIImage {
        let extent = image.extent
        var output = image
        if exposure != 0 {
            output = output.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure])
        }
        // Core Image works in linear light. Contrast and tints are chosen by eye,
        // so they are applied in screen scale and converted back afterwards.
        output = output
            .applyingFilter("CILinearToSRGBToneCurve")
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: contrast,
                kCIInputSaturationKey: saturation
            ])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: highlights[0] - shadows[0], y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: highlights[1] - shadows[1], z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: highlights[2] - shadows[2], w: 0),
                "inputBiasVector": CIVector(x: shadows[0], y: shadows[1], z: shadows[2], w: 0)
            ])
            .applyingFilter("CISRGBToneCurveToLinear")
        if vignette > 0 {
            output = output.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: vignette,
                kCIInputRadiusKey: 1.6
            ])
        }
        return output.cropped(to: extent)
    }
}

/// Every filter in the row, in the order shown (24 = six full rows of four).
/// The looks are modelled on the most used Instagram, VSCO and TikTok filters and on classic
/// film stocks (named in the comments), under our own names. Crisp uses `LookFilter` (simple
/// colour numbers); the rest use `GradeLook`, which protects skin and skies.
enum FilterLibrary {
    static let all: [Filter] = [
        NaturalFilter(),
        // Instagram "Clarendon": brighter, punchier, cool blue in the dark areas
        LookFilter(name: "Crisp", exposure: 0.1, contrast: 1.15, saturation: 1.2,
                   shadows: [0, 0.01, 0.04], highlights: [1, 1, 1.03]),
        // Everything below is graded in OKLab with skin and sky protection (see GradeLook).
        // Each look has its own job; no two are the same shift at different strengths.
        // Instagram "Juno": warm colours glow, cool colours calm, clean contrast
        GradeLook(name: "Glow", contrast: 0.4, vibrance: 0.35, warmth: 0.2,
                  highlightTint: T(75, 0.02),
                  bands: [B(60, width: 45, chroma: 1.2), B(140, hueShift: 12, chroma: 0.9), B(250, chroma: 0.9)],
                  bloom: 0.15),
        // Golden hour: honey light in the middle and bright tones, skies stay blue
        GradeLook(name: "Golden", brightness: 0.1, contrast: 0.2, vibrance: 0.2, warmth: 0.6,
                  midTint: T(70, 0.02), highlightTint: T(80, 0.035),
                  bands: [B(140, hueShift: -15, chroma: 0.9)], skinProtect: 0.9),
        // Bright soft pink, faces kept natural
        GradeLook(name: "Rosy", brightness: 0.12, contrast: 0.15, fade: 0.01, vibrance: 0.25, tint: 0.2,
                  shadowTint: T(300, 0.02), highlightTint: T(350, 0.025),
                  bands: [B(140, chroma: 0.75), B(25, chroma: 1.1)], skinProtect: 0.95),
        // Instagram "Lark": bright and clean, clear blues, calm greens; blacks stay black
        GradeLook(name: "Airy", brightness: 0.25, contrast: 0.25, blacks: 0.3, softWhites: 0.02, vibrance: 0.25,
                  bands: [B(250, chroma: 1.2, light: 0.03), B(140, hueShift: 10, chroma: 0.85), B(25, chroma: 0.9)]),
        // VSCO-style matte: the one look with clearly faded blacks, blue-grey shadows
        GradeLook(name: "Matte", contrast: 0.25, blacks: 0.25, fade: 0.035, softWhites: 0.03,
                  warmth: 0.1, shadowTint: T(220, 0.035), highlightTint: T(70, 0.02),
                  bands: [B(140, hueShift: -10, chroma: 0.9)]),
        // Deep and vivid: rich saturated colour, deep blue skies, clean whites
        GradeLook(name: "Punch", brightness: 0.05, contrast: 0.55, saturation: 1.3, vibrance: 0.4,
                  bands: [B(250, chroma: 1.3, light: -0.03), B(140, chroma: 1.15), B(25, chroma: 1.1)],
                  skinProtect: 0.75),
        // Fuji 400H film: cool, fresh greens and cyans, pastel colour
        GradeLook(name: "Fresh", brightness: 0.15, contrast: 0.15, saturation: 0.9, warmth: -0.2,
                  tint: -0.08, shadowTint: T(190, 0.03), highlightTint: T(150, 0.012),
                  bands: [B(140, hueShift: 12, chroma: 1.1), B(250, hueShift: -15, chroma: 0.9), B(25, chroma: 0.85)],
                  skinProtect: 0.95),
        // Instagram "Hudson": icy blue, faces kept alive
        GradeLook(name: "Frost", brightness: 0.12, contrast: 0.4, vibrance: 0.25, warmth: -0.45,
                  shadowTint: T(240, 0.03), highlightTint: T(210, 0.015),
                  bands: [B(25, chroma: 0.8), B(140, hueShift: 10, chroma: 1.1), B(250, chroma: 1.15)],
                  skinProtect: 0.95, vignette: 0.2),
        // CineStill 800T night film: cool blue-teal, red-orange highlights with a glow
        GradeLook(name: "Neon", contrast: 0.4, saturation: 1.25, vibrance: 0.3, warmth: -0.35, tint: 0.2,
                  shadowTint: T(205, 0.035), highlightTint: T(345, 0.065),
                  bands: [B(25, chroma: 1.4), B(340, chroma: 1.4), B(250, hueShift: -8, chroma: 1.1),
                          B(140, hueShift: 20, chroma: 0.9)],
                  skinProtect: 0.85, bloom: 0.3, halation: 0.5),
        // Consumer colour film (Kodak Gold style): warm, rich reds and yellows
        GradeLook(name: "Summer", brightness: 0.05, contrast: 0.3, saturation: 1.15, vibrance: 0.35, warmth: 0.15,
                  highlightTint: T(85, 0.02),
                  bands: [B(25, chroma: 1.2), B(100, chroma: 1.25), B(140, chroma: 1.1),
                          B(250, hueShift: -10, chroma: 1.1)], skinProtect: 0.9),
        // Kodak Portra film: gentle contrast, warm skin, green-cyan shadows, fine grain
        GradeLook(name: "Film", contrast: 0.2, blacks: 0.25, fade: 0.015, softWhites: 0.03, vibrance: 0.15,
                  warmth: 0.25, shadowTint: T(185, 0.035), highlightTint: T(65, 0.035),
                  bands: [B(140, hueShift: 12, chroma: 0.85), B(250, hueShift: -12, chroma: 0.85), B(55, chroma: 1.08)],
                  skinProtect: 0.3, grain: 0.02),
        // The teal-and-orange movie grade, with faces kept natural
        GradeLook(name: "Cinema", contrast: 0.35, blacks: 0.25,
                  shadowTint: T(205, 0.06), highlightTint: T(65, 0.035),
                  bands: [B(140, hueShift: 40, chroma: 0.75), B(250, hueShift: -30, chroma: 0.95), B(55, chroma: 1.15)],
                  skinProtect: 0.85),
        // Dark and rich: deep shadows, deep blue skies, teal greens, warm faces
        GradeLook(name: "Moody", brightness: -0.1, contrast: 0.5, blacks: 0.25, vibrance: 0.3,
                  shadowTint: T(200, 0.03), highlightTint: T(60, 0.02),
                  bands: [B(140, hueShift: 25, chroma: 0.8, light: -0.05), B(250, light: -0.06), B(55, chroma: 1.15)],
                  skinProtect: 0.9, vignette: 0.5),
        // Soft glow: lifted, hazy, pink-lilac light
        GradeLook(name: "Dreamy", brightness: 0.25, contrast: -0.05, fade: 0.02, softWhites: 0.03,
                  tint: 0.25, shadowTint: T(290, 0.025), highlightTint: T(350, 0.03), bloom: 0.45),
        // Dusk: orange light, violet shadows and skies
        GradeLook(name: "Sunset", contrast: 0.25, vibrance: 0.3, warmth: 0.7, tint: 0.25,
                  shadowTint: T(300, 0.015), highlightTint: T(50, 0.055),
                  bands: [B(250, hueShift: 15, chroma: 0.9)], skinProtect: 0.8),
        // 70s colour print: faded, warm, olive greens, plum shadows, strong reds
        GradeLook(name: "Retro", contrast: 0.2, blacks: 0.25, fade: 0.03, vibrance: 0.2, warmth: 0.25,
                  shadowTint: T(330, 0.025), midTint: T(60, 0.015), highlightTint: T(90, 0.02),
                  bands: [B(140, hueShift: -25, chroma: 0.85), B(250, hueShift: -25, chroma: 0.95), B(25, chroma: 1.15)],
                  skinProtect: 0.85, vignette: 0.4),
        // Old sepia print
        GradeLook(name: "Antique", contrast: 0.45, blacks: 0.3, softWhites: 0.03, saturation: 0.5,
                  shadowTint: T(45, 0.025), midTint: T(65, 0.05), highlightTint: T(80, 0.04),
                  skinProtect: 0.5, grain: 0.015, vignette: 0.6),
        GradeLook(name: "Warm", contrast: 0.1, warmth: 0.6, tint: 0.08),
        // Clean cool daylight: blue-grey shadows, crisp whites, faces kept warm
        GradeLook(name: "Cool", brightness: 0.05, contrast: 0.25, warmth: -0.9, tint: -0.05,
                  shadowTint: T(230, 0.03), highlightTint: T(205, 0.012),
                  bands: [B(250, chroma: 1.1), B(55, chroma: 0.9)], skinProtect: 0.95),
        // Bright and colourful: light, airy colour that jumps
        GradeLook(name: "Pop", brightness: 0.3, contrast: 0.1, saturation: 1.25, vibrance: 0.5, tint: 0.12,
                  highlightTint: T(350, 0.015),
                  bands: [B(250, hueShift: -15, chroma: 1.2, light: 0.03), B(140, hueShift: -15, chroma: 1.2),
                          B(25, hueShift: -8, chroma: 1.15)], skinProtect: 0.9),
        // Black and white, skies a little deeper than the eye sees them
        GradeLook(name: "B&W", contrast: 0.45, blacks: 0.3, fade: 0.02, mono: [0.5, 0.45, 0.05]),
        // Dark dramatic black and white: red-filter skies, dark corners
        GradeLook(name: "Noir", contrast: 0.9, blacks: 0.5, mono: [0.6, 0.35, 0.05],
                  grain: 0.01, vignette: 1)
    ]

    /// Builds every graded look's lookup table in the background, so opening the filter row
    /// never stalls the camera screen
    static func prepareInBackground() {
        DispatchQueue.global(qos: .utility).async {
            for case let look as GradeLook in all { look.prepare() }
        }
    }

    private static func T(_ hue: Double, _ amount: Double) -> GradeLook.Tint { .init(hue: hue, amount: amount) }
    private static func B(_ hue: Double, width: Double = 30, hueShift: Double = 0, chroma: Double = 1,
                          light: Double = 0) -> GradeLook.Band {
        .init(hue: hue, width: width, hueShift: hueShift, chroma: chroma, light: light)
    }
}
