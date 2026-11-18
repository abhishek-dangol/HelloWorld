import AVFoundation
import CoreImage
import Vision

/// Background blur for the Photo tab: the shot is a normal full-size photo and the blur is
/// drawn on it afterwards, so the photo keeps its size.
/// - Back camera: the way the Camera app's Portrait mode does it. The photo comes with a depth
///   map and Apple's own Portrait filter draws the blur; the live picture shows a lighter
///   stand-in made from the live depth map.
/// - Selfie camera: the person is found in the picture and everything else is blurred evenly,
///   live and in the saved photo alike.
final class PortraitBlur {
    /// The f-numbers the Photo tab's slider offers (lower = stronger blur), as in Portrait mode
    static let apertureRange: ClosedRange<Float> = 1.4...16

    private let lock = NSLock()
    private var liveDisparity: CVPixelBuffer?
    private var smoothedFocus: Float?
    private var lastFocusPoint: CGPoint?
    /// Finds the person in a live frame. Measured on iPhone 18 Pro Max: 5-10 ms a frame.
    private lazy var livePersonRequest = Self.personRequest(.balanced)
    /// Finds the person in a saved photo, with a finer outline
    private lazy var photoPersonRequest = Self.personRequest(.accurate)

    private static func personRequest(_ quality: VNGeneratePersonSegmentationRequest.QualityLevel) -> VNGeneratePersonSegmentationRequest {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = quality
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }

    func reset() {
        lock.lock()
        liveDisparity = nil
        smoothedFocus = nil
        lastFocusPoint = nil
        lock.unlock()
    }

    /// Keeps the newest live depth map (back camera only; the selfie camera has none).
    func store(_ depthData: AVDepthData) {
        let map = depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32).depthDataMap
        lock.lock()
        liveDisparity = map
        lock.unlock()
    }

    /// The newest live depth map, for a shot that will arrive without its own depth.
    func newestDepth() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return liveDisparity
    }

    // MARK: - Live picture

    /// Live blur from the live depth map. `point` is where to focus in the camera frame as it
    /// arrives (sideways, normalized, origin top-left). Things further away than that spot
    /// blur, more the further they are; nearer things stay sharp, as Apple's filter does.
    func livePreview(_ frame: CIImage, focusAt point: CGPoint, aperture: Float) -> CIImage {
        lock.lock()
        let map = liveDisparity
        lock.unlock()
        guard let map = map, let focus = focusDisparity(in: map, at: point) else { return frame }

        let depth = CIImage(cvPixelBuffer: map, options: [.colorSpace: NSNull()])
        // Disparity is 1/distance in metres. The mask is 0 at the focus distance and 1 once
        // something is `fullGap` further away in those units; the blur grows evenly between.
        let strength = depthBlur(aperture: aperture, extent: frame.extent)
        let gain = 1 / strength.fullGap
        let row = CIVector(x: -gain, y: 0, z: 0, w: 0)
        let bias = CGFloat(focus) * gain - 0.04
        let mask = depth.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": row, "inputGVector": row, "inputBVector": row,
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1)
        ]).applyingFilter("CIColorClamp").cropped(to: depth.extent)
        return blurred(frame, mask: mask, radius: strength.radius)
    }

    /// Live blur for the selfie camera: the person stays sharp and everything else blurs evenly.
    func livePreview(_ frame: CIImage, personIn pixelBuffer: CVPixelBuffer, aperture: Float) -> CIImage {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        guard (try? handler.perform([livePersonRequest])) != nil,
              let person = livePersonRequest.results?.first?.pixelBuffer else { return frame }
        return blurredAround(person, in: frame, aperture: aperture)
    }

    /// The same blur on the saved selfie (already turned upright), from a finer outline.
    func finishedPhoto(_ upright: CIImage, aperture: Float) -> CIImage {
        let handler = VNImageRequestHandler(ciImage: upright, options: [:])
        guard (try? handler.perform([photoPersonRequest])) != nil,
              let person = photoPersonRequest.results?.first?.pixelBuffer else { return upright }
        return blurredAround(person, in: upright, aperture: aperture)
    }

    /// `person` is the outline picture (white = person), covering the whole of `image`.
    private func blurredAround(_ person: CVPixelBuffer, in image: CIImage, aperture: Float) -> CIImage {
        // Nobody in view: leave the picture alone rather than blurring all of it
        guard coverage(of: person) > 0.02 else { return image }
        // White = blur. Fully sharp inside the person, fully blurred a little outside the edge.
        let outline = CIImage(cvPixelBuffer: person, options: [.colorSpace: NSNull()])
        let row = CIVector(x: -2.5, y: 0, z: 0, w: 0)
        let mask = outline.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": row, "inputGVector": row, "inputBVector": row,
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 1.5, y: 1.5, z: 1.5, w: 1)
        ]).applyingFilter("CIColorClamp").cropped(to: outline.extent)
        return blurred(image, mask: mask, radius: personRadius(aperture: aperture, extent: image.extent))
    }

    /// The slider's f-number as an f-number of Apple's Portrait filter, so that the same number
    /// looks the same in Photo and in Video. Measured on iPhone 18 Pro Max (subject at arm's
    /// length, a room behind): both blurs grow with the distance gap and shrink with the
    /// f-number, and at the same f-number the Portrait filter blurs 5.6 times as much as
    /// Cinematic Video. So from f/2 up the slider's number is multiplied by that (f/2 = Portrait
    /// f/11.2, beyond what the filter itself offers from f/4: see finishedPhoto). Below f/2,
    /// which only Photo has, the strength climbs to the filter's full f/1.4.
    static func portraitAperture(forSlider aperture: Float) -> Float {
        let atTwo = 2 * portraitPerCinematic
        if aperture >= 2 { return aperture * portraitPerCinematic }
        let lowest = apertureRange.lowerBound
        let share = log(2 / max(aperture, lowest)) / log(2 / lowest)
        return atTwo * pow(lowest / atTwo, share)
    }

    private static let portraitPerCinematic: Float = 5.6
    /// The Portrait filter's own blur, measured: pixels of blur radius on a 1080-wide picture,
    /// per 1/metre of distance gap, at f/1. It never goes past maxRadius.
    private static let radiusPerGap: Float = 25
    private static let maxRadius: Float = 16
    /// The largest distance gap the live blur tells apart (1/metres)
    private static let widestGap: Float = 3
    /// The gap the selfie blur stands for: a face at arm's length, a room behind. Measured
    /// against selfie Cinematic Video with this value: equal on things a step behind the
    /// person, a third weaker on the far wall, stronger on things right beside them.
    private static let selfieGap: Float = 2

    /// The live depth blur for the slider's f-number: the strongest radius in pixels (in
    /// proportion to the picture's size) and the distance gap at which it is reached.
    private func depthBlur(aperture: Float, extent: CGRect) -> (radius: CGFloat, fullGap: CGFloat) {
        let perGap = Self.radiusPerGap / Self.portraitAperture(forSlider: aperture)
        let radius = min(perGap * Self.widestGap, Self.maxRadius)
        return (CGFloat(radius) * Self.viewWidth(of: extent) / 1080, CGFloat(radius / perGap))
    }

    /// The width of the 9:16 view inside a picture: Video is 9:16, and a 3:4 selfie photo is
    /// shown and saved cut to that shape, so blur sizes are worked out against it.
    private static func viewWidth(of extent: CGRect) -> CGFloat {
        min(min(extent.width, extent.height), max(extent.width, extent.height) * 9 / 16)
    }

    /// The even blur around a person for the slider's f-number, in pixels.
    private func personRadius(aperture: Float, extent: CGRect) -> CGFloat {
        let radius = min(Self.radiusPerGap / Self.portraitAperture(forSlider: aperture) * Self.selfieGap, Self.maxRadius)
        return CGFloat(radius) * Self.viewWidth(of: extent) / 1080
    }

    /// `mask` must have a finite size (a colour matrix with a bias makes an endless picture,
    /// so crop it back first): it is stretched over the frame here.
    private func blurred(_ frame: CIImage, mask: CIImage, radius: CGFloat) -> CIImage {
        let extent = frame.extent
        let sizedMask = mask.clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width,
                                               y: extent.height / mask.extent.height))
            .cropped(to: extent)
        return frame.clampedToExtent().applyingFilter("CIMaskedVariableBlur", parameters: [
            "inputMask": sizedMask,
            "inputRadius": radius
        ]).cropped(to: extent)
    }

    /// The disparity at the focus spot: the middle value of a small patch, eased over time so
    /// the blur does not flicker. A new focus spot takes effect at once.
    private func focusDisparity(in map: CVPixelBuffer, at point: CGPoint) -> Float? {
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return smoothedFocus }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        let centreX = min(max(Int(point.x * CGFloat(width)), 0), width - 1)
        let centreY = min(max(Int(point.y * CGFloat(height)), 0), height - 1)
        var values: [Float] = []
        for y in max(centreY - 4, 0)...min(centreY + 4, height - 1) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in max(centreX - 4, 0)...min(centreX + 4, width - 1) where row[x].isFinite && row[x] > 0 {
                values.append(row[x])
            }
        }
        guard !values.isEmpty else { return smoothedFocus }
        values.sort()
        let sample = values[values.count / 2]
        if let previous = smoothedFocus, lastFocusPoint == point {
            smoothedFocus = previous * 0.8 + sample * 0.2
        } else {
            smoothedFocus = sample
        }
        lastFocusPoint = point
        return smoothedFocus
    }

    /// Share of the mask that is a person (sampled, not every pixel).
    private func coverage(of mask: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return 0 }
        let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask)
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        var total = 0, count = 0
        for y in stride(from: 0, to: height, by: 8) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: 0, to: width, by: 8) {
                total += Int(row[x])
                count += 1
            }
        }
        return count > 0 ? Float(total) / Float(count * 255) : 0
    }

    // MARK: - Saved photo

    /// The highest f-number Apple's Portrait filter takes
    private static let strongestFilterNumber: Float = 22

    /// Multiplies every value of a disparity map.
    private static func scale(_ map: CVPixelBuffer, by factor: Float) {
        CVPixelBufferLockBaseAddress(map, [])
        defer { CVPixelBufferUnlockBaseAddress(map, []) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in 0..<width { row[x] *= factor }
        }
    }

    /// The finished blur on a full-size back-camera photo, drawn by Apple's own Portrait filter
    /// from the depth map (and the person outline, when one came with the shot). `upright` is
    /// the photo already turned upright. `point` is where to focus in that picture (normalized,
    /// origin top-left): things further away than that spot blur. Returns nil when the shot
    /// carries no depth.
    func finishedPhoto(_ upright: CIImage, photo: AVCapturePhoto, orientation: CGImagePropertyOrientation,
                       aperture: Float, focusAt point: CGPoint, context: CIContext) -> CIImage? {
        guard let depthData = photo.depthData else { return nil }
        let map = depthData.applyingExifOrientation(orientation)
            .converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32).depthDataMap
        // The filter stops at f/22. Its blur follows gap / f-number, so a weaker blur than that
        // is had by shrinking the distances it is told instead.
        let wanted = Self.portraitAperture(forSlider: aperture)
        let filterAperture = min(wanted, Self.strongestFilterNumber)
        if filterAperture < wanted { Self.scale(map, by: filterAperture / wanted) }
        let matte = photo.portraitEffectsMatte.map {
            CIImage(cvPixelBuffer: $0.applyingExifOrientation(orientation).mattingImage)
        }
        return portraitFiltered(upright, disparity: CIImage(cvPixelBuffer: map), matte: matte,
                                filterAperture: filterAperture, focusAt: point, context: context)
    }

    /// The same finished blur for a shot that came without depth (photos over 12 MP do):
    /// drawn from the live depth map kept at the shutter press, which arrives sideways like
    /// the photo's own pixels, and from the person's outline found in the photo itself.
    func finishedPhoto(_ upright: CIImage, liveDepth: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                       aperture: Float, focusAt point: CGPoint, context: CIContext) -> CIImage? {
        // A copy: the live picture may still be drawing from this map
        guard let map = Self.copy(of: liveDepth) else { return nil }
        let wanted = Self.portraitAperture(forSlider: aperture)
        let filterAperture = min(wanted, Self.strongestFilterNumber)
        if filterAperture < wanted { Self.scale(map, by: filterAperture / wanted) }
        var disparity = CIImage(cvPixelBuffer: map).oriented(orientation)
        disparity = disparity.transformed(by: CGAffineTransform(translationX: -disparity.extent.minX,
                                                                y: -disparity.extent.minY))
        return portraitFiltered(upright, disparity: disparity, matte: personMatte(in: upright),
                                filterAperture: filterAperture, focusAt: point, context: context)
    }

    /// The person's outline in a photo, at half the photo's size like the outline the camera
    /// sends with a depth shot. Nil when nobody is in view.
    private func personMatte(in upright: CIImage) -> CIImage? {
        let handler = VNImageRequestHandler(ciImage: upright, options: [:])
        guard (try? handler.perform([photoPersonRequest])) != nil,
              let person = photoPersonRequest.results?.first?.pixelBuffer,
              coverage(of: person) > 0.02 else { return nil }
        let outline = CIImage(cvPixelBuffer: person, options: [.colorSpace: NSNull()])
        return outline.transformed(by: CGAffineTransform(scaleX: upright.extent.width / 2 / outline.extent.width,
                                                         y: upright.extent.height / 2 / outline.extent.height))
    }

    private static func copy(of map: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        var made: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, CVPixelBufferGetPixelFormatType(map),
                            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary, &made)
        guard let result = made else { return nil }
        CVPixelBufferLockBaseAddress(map, .readOnly)
        CVPixelBufferLockBaseAddress(result, [])
        defer {
            CVPixelBufferUnlockBaseAddress(result, [])
            CVPixelBufferUnlockBaseAddress(map, .readOnly)
        }
        guard let from = CVPixelBufferGetBaseAddress(map), let to = CVPixelBufferGetBaseAddress(result) else { return nil }
        let fromRow = CVPixelBufferGetBytesPerRow(map), toRow = CVPixelBufferGetBytesPerRow(result)
        for y in 0..<height {
            memcpy(to.advanced(by: y * toRow), from.advanced(by: y * fromRow), min(fromRow, toRow))
        }
        return result
    }

    /// Apple's Portrait filter on an upright photo. `disparity` and `matte` are upright too.
    private func portraitFiltered(_ upright: CIImage, disparity: CIImage, matte: CIImage?, filterAperture: Float,
                                  focusAt point: CGPoint, context: CIContext) -> CIImage? {
        guard let filter = context.depthBlurEffectFilter(for: upright, disparityImage: disparity,
                                                         portraitEffectsMatte: matte, orientation: .up,
                                                         options: nil) else { return nil }
        filter.setValue(filterAperture, forKey: "inputAperture")
        // The filter's focus box is normalized with the origin at the bottom-left
        // (worked out with a four-distance test picture)
        let side: CGFloat = 0.1
        let x = min(max(point.x - side / 2, 0), 1 - side)
        let y = min(max(1 - point.y - side / 2, 0), 1 - side)
        filter.setValue(CIVector(x: x, y: y, z: side, w: side), forKey: "inputFocusRect")
        return filter.outputImage?.cropped(to: upright.extent)
    }
}
