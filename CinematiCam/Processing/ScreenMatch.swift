import CoreImage

/// Makes a still photo look like the live picture that was on screen when the shutter was
/// pressed.
///
/// The iPhone develops a still differently from its live picture. Measured on real pairs
/// (2026-11-18): the still's dark areas come out up to half as bright, and a selfie has about
/// a tenth less colour, while the middle and bright tones agree. The difference is the same
/// kind of change all over the picture, so one dark-to-light curve and one colour-strength
/// number for the whole photo bring every area back to what the screen showed.
enum ScreenMatch {
    /// A picture as a small grid of colours, the way a screen shows them: 0 is black, 1 white
    struct Reading {
        var red: [Float], green: [Float], blue: [Float]

        /// How light each part is
        var levels: [Float] {
            (0..<red.count).map { ScreenMatch.light(red[$0], green[$0], blue[$0]) }
        }
        var averageLevel: Float {
            let levels = levels
            return levels.reduce(0, +) / Float(max(levels.count, 1))
        }
        /// How colourful the picture is: 0 for a grey picture
        var colour: Float {
            guard !red.isEmpty else { return 0 }
            var sum: Float = 0
            for index in 0..<red.count {
                sum += max(red[index], green[index], blue[index]) - min(red[index], green[index], blue[index])
            }
            return sum / Float(red.count)
        }
    }

    /// The most the colour strength is changed, either way
    static let colourLimit: ClosedRange<Float> = 0.85...1.2

    private static let steps = 64

    static func light(_ red: Float, _ green: Float, _ blue: Float) -> Float {
        min(max(0.2126 * red + 0.7152 * green + 0.0722 * blue, 0), 1)
    }

    static func reading(of image: CIImage, context: CIContext) -> Reading? {
        let longSide = max(image.extent.width, image.extent.height)
        guard longSide > 0, !image.extent.isInfinite,
              let screenSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let small = image.applyingFilter("CILanczosScaleTransform",
                                         parameters: [kCIInputScaleKey: 48 / longSide, kCIInputAspectRatioKey: 1.0])
        // Inside the edge, where the shrunken picture fades out
        let bounds = small.extent.insetBy(dx: 2, dy: 2).integral
        let width = Int(bounds.width), height = Int(bounds.height)
        guard width > 0, height > 0 else { return nil }
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes {
            context.render(small, toBitmap: $0.baseAddress!, rowBytes: width * 16, bounds: bounds,
                           format: .RGBAf, colorSpace: screenSpace)
        }
        var reading = Reading(red: [], green: [], blue: [])
        for index in stride(from: 0, to: pixels.count, by: 4) {
            reading.red.append(min(max(pixels[index], 0), 1))
            reading.green.append(min(max(pixels[index + 1], 0), 1))
            reading.blue.append(min(max(pixels[index + 2], 0), 1))
        }
        return reading
    }

    /// The curve that turns the photo's spread of dark and light into the live picture's, as
    /// 64 steps from black to white. Nil when the two already agree.
    static func toneCurve(from still: [Float], to live: [Float]) -> [Float]? {
        guard !still.isEmpty, !live.isEmpty else { return nil }
        let stillSorted = still.sorted(), liveSorted = live.sorted()
        func level(_ sorted: [Float], _ share: Float) -> Float {
            sorted[min(sorted.count - 1, Int(share * Float(sorted.count - 1) + 0.5))]
        }
        // How far a level may move, as a screen shows it: 0.75 stops either way, and in the
        // dark areas a fixed step instead. The still's darks sit a near-constant step below
        // the live picture's (0.03 against 0.06, 0.12 against 0.18), which is far more than
        // 0.75 stops down there, so the old limit left them too dark. Still too little to
        // spoil a photo if a reading is off.
        let limit = powf(2, 0.75 / 2.2), step: Float = 0.07
        // Black stays black and white stays white; in between, the darkest tenth of the photo
        // becomes as light as the darkest tenth of the live picture, and so on up
        var points: [(x: Float, y: Float)] = [(0, 0)]
        for share: Float in [0.02, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.98] {
            let x = level(stillSorted, share)
            guard x - points[points.count - 1].x >= 0.02, x <= 0.98 else { continue }
            let lowest = max(min(x / limit, x - step), 0), highest = min(max(x * limit, x + step), 1)
            let y = min(max(level(liveSorted, share), lowest), highest)
            points.append((x, max(y, points[points.count - 1].y)))
        }
        points.append((1, 1))

        var curve = [Float](repeating: 0, count: steps)
        var segment = 0
        for index in 0..<steps {
            let x = Float(index) / Float(steps - 1)
            while segment < points.count - 2, x > points[segment + 1].x { segment += 1 }
            let from = points[segment], to = points[segment + 1]
            curve[index] = from.y + (to.y - from.y) * (x - from.x) / (to.x - from.x)
        }
        // No step much steeper or flatter than the photo's own, so nothing bands or goes flat
        let even = 1 / Float(steps - 1)
        var rises = (1..<steps).map { min(max(curve[$0] - curve[$0 - 1], even / 3), even * 3) }
        let total = rises.reduce(0, +)
        if total < 1 { rises = rises.map { $0 / total } }
        for index in 1..<steps { curve[index] = min(curve[index - 1] + rises[index - 1], 1) }
        // Round off the corners
        for _ in 0..<2 {
            let before = curve
            for index in 1..<(steps - 1) {
                curve[index] = (before[index - 1] + 2 * before[index] + before[index + 1]) / 4
            }
        }
        let change = (0..<steps).map { abs(curve[$0] - Float($0) * even) }.max() ?? 0
        return change >= 0.01 ? curve : nil
    }

    /// Where the dark-area colour strength hands over to the light-area one, as levels
    private static let colourBlend: (from: Float, to: Float) = (0.25, 0.55)

    private static func colour(of reading: Reading, levels: [Float], in band: ClosedRange<Float>) -> (colour: Float, share: Float) {
        var sum: Float = 0, count: Float = 0
        for index in 0..<levels.count where band.contains(levels[index]) {
            sum += max(reading.red[index], reading.green[index], reading.blue[index])
                - min(reading.red[index], reading.green[index], reading.blue[index])
            count += 1
        }
        return (count > 0 ? sum / count : 0, count / Float(max(levels.count, 1)))
    }

    /// How much stronger (above 1) or weaker the photo's colour has to be to match the live
    /// picture, once the curve is on it: one number for the dark areas and one for the light
    /// areas. The still loses colour mostly in its light areas (a face), hardly in its darks,
    /// so one number for everything made dark clothes too colourful. Worked out on the small
    /// grid, with the same sums the full photo then goes through.
    static func colourGains(still: Reading, curve: [Float]?, live: Reading) -> (dark: Float, light: Float) {
        func throughCurve(_ value: Float) -> Float {
            guard let curve else { return value }
            let place = min(max(value, 0), 1) * Float(curve.count - 1)
            let index = min(Int(place), curve.count - 2)
            return curve[index] + (curve[index + 1] - curve[index]) * (place - Float(index))
        }
        func toLinear(_ value: Float) -> Float {
            value <= 0.04045 ? value / 12.92 : powf((value + 0.055) / 1.055, 2.4)
        }
        func toScreen(_ value: Float) -> Float {
            let held = min(max(value, 0), 1)
            return held <= 0.0031308 ? held * 12.92 : 1.055 * powf(held, 1 / 2.4) - 0.055
        }
        let curved = Reading(red: still.red.map(throughCurve), green: still.green.map(throughCurve),
                             blue: still.blue.map(throughCurve))
        let curvedLevels = curved.levels, liveLevels = live.levels
        // The photo's small grid with the two strengths on it, exactly as `matched` does it
        func result(dark: Float, light: Float) -> Reading {
            var out = curved
            for index in 0..<curved.red.count {
                let share = min(max((curvedLevels[index] - colourBlend.from) / (colourBlend.to - colourBlend.from), 0), 1)
                let gain = dark + (light - dark) * share
                let red = toLinear(curved.red[index]), green = toLinear(curved.green[index]), blue = toLinear(curved.blue[index])
                let grey = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                out.red[index] = toScreen(grey + (red - grey) * gain)
                out.green[index] = toScreen(grey + (green - grey) * gain)
                out.blue[index] = toScreen(grey + (blue - grey) * gain)
            }
            return out
        }
        // A nearly grey picture has too little colour to measure a ratio from: the small
        // added amount pulls the answer towards "leave it" there
        let floor: Float = 0.02
        func wanted(_ liveColour: Float, _ now: Float) -> Float {
            min(max((liveColour + floor) / (now + floor), colourLimit.lowerBound), colourLimit.upperBound)
        }
        let everything: ClosedRange<Float> = 0...1
        let bands: [ClosedRange<Float>] = [0...0.3, 0.5...1]
        let overall = wanted(colour(of: live, levels: liveLevels, in: everything).colour,
                             colour(of: curved, levels: curvedLevels, in: everything).colour)
        // A band too small to measure (under a twelfth of the picture) takes the overall number
        var targets = [Float](), gains = [Float]()
        for band in bands {
            let liveBand = colour(of: live, levels: liveLevels, in: band)
            let stillBand = colour(of: curved, levels: curvedLevels, in: band)
            let ratio = min(liveBand.share, stillBand.share) >= 1 / 12 ? wanted(liveBand.colour, stillBand.colour) : overall
            gains.append(ratio)
            targets.append(ratio * stillBand.colour)
        }
        for _ in 0..<3 {
            let now = result(dark: gains[0], light: gains[1])
            for (index, band) in bands.enumerated() {
                let got = colour(of: now, levels: curvedLevels, in: band).colour
                guard got > 0.0005, targets[index] > 0.0005 else { continue }
                gains[index] = min(max(gains[index] * targets[index] / got, 0.75), 1.35)
            }
        }
        return (gains[0], gains[1])
    }

    /// The photo with the live picture's dark-to-light spread and colour strength
    static func matched(_ photo: CIImage, to live: Reading, context: CIContext) -> CIImage {
        guard !live.red.isEmpty, let still = reading(of: photo, context: context), !still.red.isEmpty,
              let screenSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return photo }
        var output = photo
        let curve = toneCurve(from: still.levels, to: live.levels)
        if let curve {
            let table = curve.flatMap { [$0, $0, $0] }
            output = output.applyingFilter("CIColorCurves", parameters: [
                "inputCurvesData": table.withUnsafeBufferPointer { Data(buffer: $0) },
                "inputCurvesDomain": CIVector(x: 0, y: 1),
                "inputColorSpace": screenSpace,
            ])
        }
        let gains = colourGains(still: still, curve: curve, live: live)
        guard abs(gains.dark - 1) >= 0.02 || abs(gains.light - 1) >= 0.02 else { return output }
        // Every colour moves away from (or towards) the grey of the same lightness
        func strengthened(_ gain: Float) -> CIImage {
            let gain = CGFloat(gain)
            let red = 0.2126 * (1 - gain), green = 0.7152 * (1 - gain), blue = 0.0722 * (1 - gain)
            return output.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: red + gain, y: green, z: blue, w: 0),
                "inputGVector": CIVector(x: red, y: green + gain, z: blue, w: 0),
                "inputBVector": CIVector(x: red, y: green, z: blue + gain, w: 0),
            ])
        }
        // 0 in the dark areas, 1 in the light ones, by the level a screen shows
        let width = CGFloat(colourBlend.to - colourBlend.from), start = CGFloat(colourBlend.from)
        let grey = CIVector(x: 0.2126 / width, y: 0.7152 / width, z: 0.0722 / width, w: 0)
        let inLights = output
            .applyingFilter("CILinearToSRGBToneCurve")
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": grey, "inputGVector": grey, "inputBVector": grey,
                "inputBiasVector": CIVector(x: -start / width, y: -start / width, z: -start / width, w: 0)])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)])
        output = strengthened(gains.light).applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: strengthened(gains.dark), kCIInputMaskImageKey: inLights])
        return output
    }
}
