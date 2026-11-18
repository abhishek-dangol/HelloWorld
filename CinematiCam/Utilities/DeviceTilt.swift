import SwiftUI
import CoreMotion
import Combine

/// Which way up the phone is being held, read from the motion sensor so it works even
/// though the screen itself stays upright (and with the phone's rotation lock on).
/// `angle` is how far icons and labels must turn to read upright: 0, 90, -90 or 180.
final class DeviceTilt: ObservableObject {
    static let shared = DeviceTilt()

    @Published private(set) var angle: Double = 0
    /// How level the phone is, for the level line. Kept apart from `angle` so that only
    /// the level line redraws as the phone moves.
    let level = LevelReading()
    private let motion = CMMotionManager()

    private init() {
        guard motion.isAccelerometerAvailable else { return }
        // Fast enough for the level line to follow the hand smoothly
        motion.accelerometerUpdateInterval = 1.0 / 30
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let pull = data?.acceleration else { return }
            self.level.take(x: pull.x, y: pull.y)
            // Lying nearly flat or held halfway: keep the last answer
            let x = pull.x, y = pull.y
            var next = self.angle
            if abs(x) > 0.75, abs(y) < 0.5 {
                next = x < 0 ? 90 : -90
            } else if abs(y) > 0.75, abs(x) < 0.5 {
                next = y < 0 ? 0 : 180
            }
            if next != self.angle { self.angle = next }
        }
    }
}

/// The phone's lean away from straight, measured the way the iPhone Camera's level does:
/// against the nearest upright or sideways hold.
final class LevelReading: ObservableObject {
    /// Degrees off level; nil while the phone lies too flat to tell
    @Published private(set) var lean: Double?
    /// The hold the lean is measured against: 0, 90, -90 or 180 (same sense as DeviceTilt.angle)
    @Published private(set) var hold: Double = 0
    /// Level for long enough that the line can leave
    @Published private(set) var settled = false

    static let levelWithin = 1.0
    private var smoothX = 0.0
    private var smoothY = -1.0
    private var levelSince: Date?

    var isLevel: Bool { lean.map { abs($0) < Self.levelWithin } ?? false }

    fileprivate func take(x: Double, y: Double) {
        // Even out the sensor's jitter
        smoothX = smoothX * 0.8 + x * 0.2
        smoothY = smoothY * 0.8 + y * 0.2
        guard (smoothX * smoothX + smoothY * smoothY).squareRoot() > 0.5 else {
            if lean != nil { lean = nil }
            levelSince = nil
            return
        }
        // The turn that makes something on screen stand upright in the room. Matches
        // DeviceTilt.angle at the four straight holds (left edge down = +90).
        let upright = atan2(-smoothX, -smoothY) * 180 / .pi
        let nearest = (upright / 90).rounded() * 90
        let wasLevel = isLevel
        // Steps of a tenth of a degree, so a still phone does not redraw
        let next = ((upright - nearest) * 10).rounded() / 10
        if next != lean { lean = next }
        let nextHold = nearest == -180 ? 180 : nearest
        if nextHold != hold { hold = nextHold }

        if isLevel {
            if !wasLevel {
                levelSince = Date()
                HapticFeedback.impact()
            }
            if !settled, let since = levelSince, Date().timeIntervalSince(since) > 1 { settled = true }
        } else {
            levelSince = nil
            if settled { settled = false }
        }
    }
}

/// The iPhone Camera's level: two short marks fixed to the screen and a longer line
/// between them that stays level with the horizon. Straight = one yellow line, which
/// then fades away until the phone leans again.
struct LevelLine: View {
    @ObservedObject private var level = DeviceTilt.shared.level
    /// Further off than this and the line stays away, as it is no help
    private let showWithin = 15.0

    var body: some View {
        let lean = level.lean ?? 0
        let colour = level.isLevel ? Color.yellow : Color.white
        ZStack {
            HStack(spacing: 100) {
                mark(width: 20, colour: colour)
                mark(width: 20, colour: colour)
            }
            mark(width: 92, colour: colour)
                .rotationEffect(.degrees(level.isLevel ? 0 : lean))
        }
        .rotationEffect(.degrees(level.hold))
        .opacity(level.lean == nil || abs(lean) > showWithin || level.settled ? 0 : 1)
        .animation(.easeOut(duration: 0.25), value: level.settled)
        .animation(.easeOut(duration: 0.25), value: level.lean == nil || abs(lean) > showWithin)
        .allowsHitTesting(false)
    }

    private func mark(width: CGFloat, colour: Color) -> some View {
        Capsule()
            .fill(colour)
            .frame(width: width, height: 1.5)
            .shadow(color: .black.opacity(0.35), radius: 1)
    }
}

private struct TurnsWithPhone: ViewModifier {
    @ObservedObject private var tilt = DeviceTilt.shared

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(tilt.angle))
            .animation(.easeInOut(duration: 0.25), value: tilt.angle)
    }
}

extension View {
    /// Turns in place when the phone is held sideways, like the Camera app's icons.
    func turnsWithPhone() -> some View { modifier(TurnsWithPhone()) }
}

extension UIImage {
    /// The same picture, marked to show the right way up when it was shot with the phone
    /// held at `angle` (DeviceTilt.angle). No pixels are redrawn: only the "which way is
    /// up" tag changes, which Photos and every viewer follow.
    func uprightForPhone(heldAt angle: Double) -> UIImage {
        guard let cgImage = cgImage, imageOrientation == .up else { return self }
        let way: UIImage.Orientation
        switch angle {
        case 90: way = .left
        case -90: way = .right
        case 180: way = .down
        default: return self
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: way)
    }

    /// The same picture flipped left-to-right as it is shown (Mirror selfies off). The pixels
    /// are redrawn. A picture tagged as shot sideways is shown a quarter turn round, so its
    /// left-to-right is the stored picture's top-to-bottom.
    func flippedSideToSide() -> UIImage {
        guard let cgImage = cgImage else { return self }
        let width = cgImage.width, height = cgImage.height
        let upDown = imageOrientation == .left || imageOrientation == .right
        func redraw(in space: CGColorSpace, bits: Int) -> CGImage? {
            var info = CGImageAlphaInfo.noneSkipLast.rawValue
            if bits == 16 { info |= CGBitmapInfo.byteOrder16Little.rawValue }
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bits,
                                          bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
            if upDown {
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: 1, y: -1)
            } else {
                context.translateBy(x: CGFloat(width), y: 0)
                context.scaleBy(x: -1, y: 1)
            }
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage()
        }
        // The picture's own colours at its own depth first, so nothing is lost; then its
        // colours at normal depth; then plain sRGB, which can always be drawn into
        let own = cgImage.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
        var flipped: CGImage?
        if let own = own {
            if cgImage.bitsPerComponent > 8 { flipped = redraw(in: own, bits: 16) }
            if flipped == nil { flipped = redraw(in: own, bits: 8) }
        }
        if flipped == nil, let plain = CGColorSpace(name: CGColorSpace.sRGB) {
            flipped = redraw(in: plain, bits: 8)
        }
        guard let flipped = flipped else {
            print("Mirror selfies off: this photo could not be flipped, it is saved as shown on screen")
            return self
        }
        return UIImage(cgImage: flipped, scale: scale, orientation: imageOrientation)
    }
}

/// The sun beside the focus box. It rides up (brighter) or down (darker) a thin line that
/// shows once the brightness has been moved. Sizes are estimates of the iPhone Camera's.
struct BrightnessSun: View {
    /// Stops brighter (+) or darker (-) than the camera's own pick
    let shift: Float
    let showsTrack: Bool

    private static let travel: CGFloat = 60
    private static let gapAroundSun: CGFloat = 28

    var body: some View {
        let offset = -CGFloat(shift / CameraManager.brightnessLimit) * Self.travel
        ZStack {
            if showsTrack {
                VStack(spacing: 0) {
                    Rectangle().frame(width: 1, height: max(0, Self.travel + offset - Self.gapAroundSun / 2))
                    Color.clear.frame(width: 1, height: Self.gapAroundSun)
                    Rectangle().frame(width: 1, height: max(0, Self.travel - offset - Self.gapAroundSun / 2))
                }
                .foregroundColor(.yellow)
            }
            Image(systemName: "sun.max.fill")
                .font(.system(size: 17))
                .foregroundColor(.yellow)
                .offset(y: offset)
        }
        .frame(width: 28, height: Self.travel * 2 + Self.gapAroundSun)
        .shadow(color: .black.opacity(0.4), radius: 1.5)
    }
}
