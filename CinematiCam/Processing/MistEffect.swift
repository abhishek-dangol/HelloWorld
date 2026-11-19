import CoreImage

/// The Mist slider: the look of a mist (diffusion) glass in front of the lens, such as a
/// Black Pro-Mist.
///
/// A mist glass scatters a share of ALL the light that passes through it. Most of it lands
/// close by (skin and fine contrast soften, detail stays), some lands far away (lights get a
/// wide soft halo and nearby darks lift into a haze). So the picture is mixed with blurred
/// copies of itself at four sizes, in linear light, where a lamp is many times brighter than
/// a face and so glows many times more, the way it does through glass.
enum MistEffect {
    /// The share of the light that is scattered with the slider at full
    static let fullScatter = 0.42

    /// `amount` is the slider, 0 (off) to 1. Sizes follow the picture's long side, so video
    /// frames and big photos look the same.
    /// `keepBlacks` is the "Black" in Black Pro-Mist: how much of the broad grey fog is kept
    /// out of the dark areas (0 = plain mist, darks lift into haze).
    static func apply(to image: CIImage, amount: Double, keepBlacks: Double = 0.8) -> CIImage {
        let extent = image.extent
        guard amount > 0.005, !extent.isInfinite, extent.width > 0 else { return image }
        let scatter = min(1, amount) * fullScatter
        // Sizes go by the long side: a live frame arrives sideways (its width is the long
        // side) and a photo upright (its width is the short side), and the mist has to reach
        // equally far in both or the photo does not match the screen
        let longSide = max(extent.width, extent.height)

        func scaled(_ input: CIImage, by gain: Double, bias: Double = 0) -> CIImage {
            input.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)])
        }
        /// `share` of `top` over `base`
        func mix(_ top: CIImage, over base: CIImage, share: Double) -> CIImage {
            top.applyingFilter("CIMix", parameters: [kCIInputBackgroundImageKey: base, kCIInputAmountKey: share])
        }

        // The scattered light is worked out on a quarter-size copy (a sixteenth of the work).
        // It is soft all over, so nothing is lost; the smooth shrink keeps small lights from
        // flickering from frame to frame.
        let small = image.applyingFilter("CILanczosScaleTransform",
                                         parameters: [kCIInputScaleKey: 0.25, kCIInputAspectRatioKey: 1])
        // A lamp is far brighter than the camera can record: it is saved as plain white, and
        // would glow no more than a white shirt does. So what is close to white gets its
        // brightness back before scattering: a little everywhere (a bright sky), and a lot
        // where the surroundings are dark, because that is a lamp at night.
        let knee = 0.8
        let white = CIVector(x: 1, y: 1, z: 1, w: 1), black = CIVector(x: 0, y: 0, z: 0, w: 1)
        func held(_ input: CIImage) -> CIImage {
            input.applyingFilter("CIColorClamp", parameters: ["inputMinComponents": black, "inputMaxComponents": white])
        }
        // Judged by the strongest of red, green and blue, so a red tail light counts too;
        // the glow keeps the light's own colour
        let bright = held(scaled(small.applyingFilter("CIMaximumComponent"), by: 1 / (1 - knee), bias: -knee / (1 - knee)))
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: small])
        // 1 where the surroundings are dark, 0 where they are as bright as a daylight scene
        let grey = CIVector(x: -0.2126 * 3.5, y: -0.7152 * 3.5, z: -0.0722 * 3.5, w: 0)
        let around = small.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: longSide * 0.08 / 4])
        let darkAround = held(around
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": grey, "inputGVector": grey, "inputBVector": grey,
                "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)]))
            .cropped(to: small.extent)
        let lamps = bright.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: darkAround])
        // source = picture + sky boost + lamp boost (a sum is twice an even mix)
        let skyBoost = 0.3, lampBoost = 16.0
        let extra = scaled(mix(scaled(lamps, by: lampBoost), over: scaled(bright, by: skyBoost), share: 0.5), by: 2)
        let source = scaled(mix(extra, over: small, share: 0.5), by: 2).clampedToExtent()
        // `share` = the reach as a share of the picture's width
        func spread(_ share: Double) -> CIImage {
            source.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: longSide * share / 4])
                .transformed(by: CGAffineTransform(scaleX: 4, y: 4))
                .cropped(to: extent)
        }
        // Four reaches, most of the light close by and a long faint tail:
        // 28% tight, 27% near, 25% wide, 20% very wide
        var haze = mix(spread(0.16), over: spread(0.055), share: 0.20 / 0.45)
        haze = mix(haze, over: spread(0.018), share: 0.45 / 0.72)
        haze = mix(haze, over: spread(0.005), share: 0.72)

        // Plain mist glass turns a daylight picture foggy: the light of the whole bright scene
        // lands on the dark areas too. A black mist glass holds that back, so a black car
        // stays black while lights still glow. Here: the broad light of the picture as it
        // was recorded (not the lamps' given-back brightness, so night halos stay) is taken
        // back out of the haze, fully in the darks and not at all from the middle tones up.
        if keepBlacks > 0 {
            let fog = around.transformed(by: CGAffineTransform(scaleX: 4, y: 4)).cropped(to: extent)
            let dark = CIVector(x: -0.2126 / 0.5, y: -0.7152 / 0.5, z: -0.0722 / 0.5, w: 0)
            let inDarks = held(image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": dark, "inputGVector": dark, "inputBVector": dark,
                "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)]))
            let takeBack = scaled(fog, by: -keepBlacks)
                .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: inDarks])
            haze = scaled(mix(takeBack, over: haze, share: 0.5), by: 2)
        }
        // Never darker than the share of the light that passes straight through
        let misted = scaled(image, by: 1 - scatter)
            .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: mix(haze, over: image, share: scatter)])
        // The middle of a light stays as bright as it was (in life it is far past white):
        // anything close to white, or above it in HDR video, keeps its own value
        let cores = scaled(image, by: 4, bias: -3)
            .applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: image])
        return cores.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: misted])
            .cropped(to: extent)
    }
}
