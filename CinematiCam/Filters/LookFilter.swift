import CoreImage

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
/// The looks are modelled on the most used Instagram and TikTok filters (named in the
/// comments), under our own names. The first few use `LookFilter` (simple colour numbers);
/// the rest use `CurveLook` (tone curves and tints), which can match photo filters more closely.
enum FilterLibrary {
    static let all: [Filter] = [
        NaturalFilter(),
        // Instagram "Clarendon": brighter, punchier, cool blue in the dark areas
        LookFilter(name: "Crisp", exposure: 0.1, contrast: 1.15, saturation: 1.2,
                   shadows: [0, 0.01, 0.04], highlights: [1, 1, 1.03]),
        // Instagram "Juno": warm colours pop, deeper darks
        LookFilter(name: "Glow", contrast: 1.1, saturation: 1.2,
                   shadows: [0.01, 0, 0], highlights: [1.04, 1, 0.94]),
        // Instagram "Valencia" / "Rise": golden light, soft darks
        LookFilter(name: "Golden", exposure: 0.15, contrast: 0.95, saturation: 1.05,
                   shadows: [0.05, 0.04, 0.02], highlights: [1.03, 0.98, 0.86]),
        // Instagram "Nashville" / TikTok "Fantasy V11": bright with a pink tint
        LookFilter(name: "Rosy", exposure: 0.15, contrast: 0.93,
                   shadows: [0.07, 0.03, 0.07], highlights: [1.03, 0.95, 0.97]),
        // Instagram "Lark": bright and airy, calmer reds, stronger blues
        LookFilter(name: "Airy", exposure: 0.25, contrast: 0.97, saturation: 0.9,
                   shadows: [0.03, 0.04, 0.05], highlights: [0.98, 1, 1.03]),
        // The matte look: lifted blacks, slightly muted colour, contrast kept
        CurveLook(name: "Matte", contrast: 0.25, saturation: 0.88,
                  shadows: [0.09, 0.085, 0.1], highlights: [0.99, 0.98, 0.97]),
        // Instagram "X-Pro II": high contrast, warm highlights, green-blue darks, dark corners
        CurveLook(name: "Punch", brightness: 0.08, contrast: 0.55, saturation: 1.3,
                  shadows: [0, 0.01, 0.03], highlights: [1, 0.97, 0.84], vignette: 0.9),
        // Instagram "1977": pink-tinted fade with lifted blacks
        CurveLook(name: "Blush", brightness: 0.1, contrast: -0.1,
                  shadows: [0.12, 0.05, 0.1], highlights: [1, 0.88, 0.9], midtones: [0.05, 0, 0.05]),
        // Instagram "Hudson": cool, bright, icy blue shadows
        CurveLook(name: "Frost", brightness: 0.12, contrast: 0.25, saturation: 0.95,
                  shadows: [0.02, 0.05, 0.12], highlights: [0.96, 1, 1],
                  shadowTint: [0, 0.02, 0.06], vignette: 0.4),
        // Instagram "Amaro": bright, warm centre, lifted shadows
        CurveLook(name: "Sunny", brightness: 0.25, contrast: 0.15, saturation: 1.15,
                  shadows: [0.04, 0.03, 0], highlights: [1, 0.97, 0.85], midtones: [0.05, 0.03, -0.03]),
        // Instagram "Toaster": burnt orange, strong contrast, dark corners
        CurveLook(name: "Toast", contrast: 0.3, saturation: 1.2,
                  shadows: [0.12, 0.02, 0], highlights: [1, 0.92, 0.75], vignette: 1),
        // Kodak Portra-style film: soft contrast, warm skin, slightly green-blue darks
        CurveLook(name: "Film", brightness: 0.05, contrast: 0.2, saturation: 0.9,
                  shadows: [0.04, 0.05, 0.06], highlights: [1, 0.97, 0.92],
                  midtones: [0.06, 0.02, -0.03], shadowTint: [-0.01, 0.03, 0.04],
                  highlightTint: [0.04, 0.02, -0.03]),
        // The teal-and-orange movie grade used all over TikTok and Reels
        CurveLook(name: "Cinema", contrast: 0.35, saturation: 1.05,
                  shadowTint: [-0.04, 0.03, 0.08], highlightTint: [0.08, 0.02, -0.08]),
        // Dark, matte, green-teal shadows, dark corners
        CurveLook(name: "Moody", brightness: -0.2, contrast: 0.45, saturation: 0.8,
                  shadows: [0, 0.03, 0.03], shadowTint: [-0.02, 0.03, 0.04], vignette: 1),
        // TikTok-style soft glow: lifted, hazy, pink-tinged bloom
        CurveLook(name: "Dreamy", brightness: 0.2, contrast: -0.15,
                  shadows: [0.06, 0.04, 0.07], highlights: [1, 0.97, 1], bloom: 0.6),
        // Orange-pink golden hour
        CurveLook(name: "Sunset", contrast: 0.3, saturation: 1.3,
                  midtones: [0.15, 0, -0.1], shadowTint: [0.05, -0.02, 0.04],
                  highlightTint: [0.1, 0, -0.1]),
        // 70s warm photo: faded browns, orange highlights, dark corners
        CurveLook(name: "Retro", contrast: 0.1, saturation: 0.95,
                  shadows: [0.14, 0.1, 0.06], highlights: [1, 0.95, 0.82],
                  midtones: [0.1, 0.03, -0.08], vignette: 0.6),
        // Instagram "Earlybird": old-photo sepia, dark corners
        CurveLook(name: "Antique", contrast: 0.2, saturation: 0.5,
                  shadows: [0.08, 0.05, 0.02], highlights: [1, 0.92, 0.72], vignette: 0.8),
        CurveLook(name: "Warm", brightness: 0.05, saturation: 1.05,
                  highlights: [1, 0.97, 0.88], midtones: [0.2, 0.05, -0.2]),
        CurveLook(name: "Cool", saturation: 1.0,
                  highlights: [0.9, 0.98, 1], midtones: [-0.2, 0, 0.2]),
        // Boosted colour and contrast
        CurveLook(name: "Pop", brightness: 0.05, contrast: 0.35, saturation: 1.5),
        // Instagram "Inkwell": black and white with strong contrast
        CurveLook(name: "B&W", brightness: 0.05, contrast: 0.4, mono: true),
        // Dark dramatic black and white with dark corners
        CurveLook(name: "Noir", brightness: -0.15, contrast: 0.7, mono: true, vignette: 1.2)
    ]
}
