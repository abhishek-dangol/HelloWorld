import Foundation
import CoreGraphics
import CoreImage
import Vision

/// Fades the fine lines just under each eye in a finished photo (2026-11-20).
///
/// Skin smoothing keeps thin lines, because it treats them as edges. Here each eye is found
/// (Apple's face points), a soft crescent is drawn below the lower eyelid, and inside it the
/// thin dark lines are filled from the lighter skin beside them. Only darker-than-neighbours
/// detail is lifted, and only by a limited amount, so the skin keeps its grain, the natural
/// shading under the eye stays, and the lower lashes are not wiped out.
///
/// Photos only: it works on one still picture, so nothing can lag behind a moving face.
enum UnderEyeLines {
    // All sizes are a share of the eye's width, so they hold for any photo size
    private static let gap: CGFloat = 0.08          // clear skin left under the lash line
    private static let coreDepth: CGFloat = 0.45    // how far down the full-strength part reaches
    private static let farDepth: CGFloat = 0.80     // how far down the faintest part reaches
    private static let endDepth: CGFloat = 0.22     // depth at the two ends of the crescent
    private static let outerReach: CGFloat = 0.15   // past the outer eye corner
    private static let innerReach: CGFloat = 0.10   // past the inner eye corner
    private static let edgeSoftness: CGFloat = 0.03
    private static let lineSize: CGFloat = 0.028    // lines up to about twice this wide are filled
    /// The most a dot may be lifted (of full brightness). Deep darks such as lashes stay dark.
    private static let mostLift: CGFloat = 0.11
    private static let layers = 6

    /// The photo with the under-eye lines faded, and how many eyes were treated.
    /// The photo must be upright. With no face found it comes back unchanged.
    static func faded(_ photo: CIImage, context: CIContext) -> (image: CIImage, eyes: Int) {
        let extent = photo.extent
        guard extent.width > 0, extent.height > 0, !extent.isInfinite else { return (photo, 0) }
        // Faces are looked for on a small copy; the points are then scaled back up
        let shrink = min(1, 1280 / max(extent.width, extent.height))
        let small = photo.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: shrink, y: shrink))
        guard let smallPicture = context.createCGImage(small, from: small.extent) else { return (photo, 0) }
        let request = VNDetectFaceLandmarksRequest()
        guard (try? VNImageRequestHandler(cgImage: smallPicture).perform([request])) != nil,
              let faces = request.results, !faces.isEmpty else { return (photo, 0) }

        var result = photo
        var eyes = 0
        for face in faces.prefix(4) {
            guard let marks = face.landmarks, let left = marks.leftEye, let right = marks.rightEye,
                  let lips = marks.outerLips else { continue }
            func points(_ region: VNFaceLandmarkRegion2D) -> [CGPoint] {
                region.pointsInImage(imageSize: extent.size).map { CGPoint(x: $0.x + extent.minX, y: $0.y + extent.minY) }
            }
            let leftPoints = points(left), rightPoints = points(right)
            guard leftPoints.count >= 4, rightPoints.count >= 4 else { continue }
            let leftCentre = mean(leftPoints), rightCentre = mean(rightPoints)
            let across = rightCentre - leftCentre
            let distance = (across.dot(across)).squareRoot()
            guard distance > 1 else { continue }
            // "along" runs from eye to eye, "down" points from the eyes to the mouth
            let along = across * (1 / distance)
            var down = CGPoint(x: along.y, y: -along.x)
            if (mean(points(lips)) - (leftCentre + rightCentre) * 0.5).dot(down) < 0 { down = down * -1 }
            let faceMiddle = (leftCentre + rightCentre) * 0.5

            for eye in [leftPoints, rightPoints] {
                if let touched = fadedUnderEye(result, eye: eye, along: along, down: down,
                                               faceMiddle: faceMiddle, within: extent) {
                    result = touched
                    eyes += 1
                }
            }
        }
        return (result, eyes)
    }

    private static func fadedUnderEye(_ photo: CIImage, eye: [CGPoint], along: CGPoint, down: CGPoint,
                                      faceMiddle: CGPoint, within extent: CGRect) -> CIImage? {
        let centre = mean(eye)
        // Each eye point as (how far along, how far down) from the eye's middle
        let placed = eye.map { (($0 - centre).dot(along), ($0 - centre).dot(down)) }
        guard let low = placed.min(by: { $0.0 < $1.0 }), let high = placed.max(by: { $0.0 < $1.0 }) else { return nil }
        let width = high.0 - low.0
        guard width > 20 else { return nil }
        let cornerDown = (low.1 + high.1) / 2
        let lowerLid = placed.filter { $0.1 > cornerDown && $0.0 > low.0 && $0.0 < high.0 }.sorted { $0.0 < $1.0 }
        // The outer corner is the one farther from the middle of the face
        let outerIsLow = abs((centre + along * low.0 - faceMiddle).dot(along)) > abs((centre + along * high.0 - faceMiddle).dot(along))
        let reachLow = (outerIsLow ? outerReach : innerReach) * width
        let reachHigh = (outerIsLow ? innerReach : outerReach) * width
        let lid = [(low.0 - reachLow, low.1), low] + lowerLid + [high, (high.0 + reachHigh, high.1)]
        func lidDown(_ x: CGFloat) -> CGFloat {
            for i in 1..<lid.count where x <= lid[i].0 {
                let t = (x - lid[i - 1].0) / max(0.001, lid[i].0 - lid[i - 1].0)
                return lid[i - 1].1 + (lid[i].1 - lid[i - 1].1) * t
            }
            return lid[lid.count - 1].1
        }

        // The crescent as nested shapes: the widest is the faintest, the smallest is full strength
        let start = lid[0].0, end = lid[lid.count - 1].0, steps = 32
        var shapes: [[CGPoint]] = []
        for layer in 0..<layers {
            let k = CGFloat(layer) / CGFloat(layers - 1)
            let middleDepth = (farDepth + (coreDepth - farDepth) * k) * width
            let sideDepth = endDepth * width * (1 - 0.5 * k)
            var top: [CGPoint] = [], bottom: [CGPoint] = []
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let x = start + (end - start) * t
                let topDown = lidDown(x) + gap * width
                let depth = sideDepth + (middleDepth - sideDepth) * sin(.pi * t)
                top.append(centre + along * x + down * topDown)
                bottom.append(centre + along * x + down * (topDown + depth))
            }
            shapes.append(top + bottom.reversed())
        }

        let soft = edgeSoftness * width
        let radius = max(1.5, lineSize * width)
        let all = shapes.flatMap { $0 }
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
              let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return nil }
        let margin = 3 * soft + radius + 2
        let area = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: -margin, dy: -margin).integral.intersection(extent)
        guard area.width >= 8, area.height >= 8 else { return nil }

        // Draw the crescent (white = full strength) in a small picture the size of the area
        let wide = Int(area.width), tall = Int(area.height)
        guard let drawing = CGContext(data: nil, width: wide, height: tall, bitsPerComponent: 8, bytesPerRow: wide,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        drawing.setFillColor(gray: 0, alpha: 1)
        drawing.fill(CGRect(x: 0, y: 0, width: wide, height: tall))
        drawing.translateBy(x: -area.minX, y: -area.minY)
        for (layer, shape) in shapes.enumerated() {
            drawing.setFillColor(gray: CGFloat(layer + 1) / CGFloat(layers), alpha: 1)
            drawing.beginPath()
            drawing.addLines(between: shape)
            drawing.closePath()
            drawing.fillPath()
        }
        guard let drawn = drawing.makeImage() else { return nil }
        let crescent = CIImage(cgImage: drawn, options: [.colorSpace: NSNull()])
            .transformed(by: CGAffineTransform(translationX: area.minX, y: area.minY))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(soft))
            .cropped(to: area)

        // Thin dark lines are filled from the lighter skin beside them (brightest nearby, then
        // darkest nearby: anything dark and narrower than the reach disappears)
        let piece = photo.cropped(to: area)
        let filled = piece.clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": radius])
            .applyingFilter("CIMorphologyMinimum", parameters: ["inputRadius": radius])
            .cropped(to: area)
        // No dot is lifted by more than the limit
        let ceiling = piece.applyingFilter("CIColorMatrix", parameters: [
            "inputBiasVector": CIVector(x: mostLift, y: mostLift, z: mostLift, w: 0)])
        let limited = filled.applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: ceiling])
        let touched = limited.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: piece, kCIInputMaskImageKey: crescent]).cropped(to: area)
        return touched.composited(over: photo)
    }

    private static func mean(_ points: [CGPoint]) -> CGPoint {
        points.reduce(CGPoint.zero, +) * (1 / CGFloat(max(1, points.count)))
    }
}

private extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
    func dot(_ b: CGPoint) -> CGFloat { x * b.x + y * b.y }
}
