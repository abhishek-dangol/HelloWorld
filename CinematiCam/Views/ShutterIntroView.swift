import AVFoundation
import SwiftUI

/// The first thing a new user sees: the front of a camera lens, full screen, with its iris shut.
/// The iris opens, the view moves through the lens onto a photo while the photo comes into focus,
/// then the app name comes into focus letter by letter.
/// Every frame is worked out from the time since the screen appeared, so any moment can be held
/// still for screenshots (debug launch argument -introTime <seconds>).
struct ShutterIntroView: View {
    var onContinue: () -> Void

    @State private var start: Date?
    @State private var finished = false
    @State private var sounds = ShutterSounds()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let photo = IntroPhoto.current
    private let style = TitleStyle.current

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: finished || IntroDebug.time != nil)) { timeline in
            frame(at: time(at: timeline.date))
        }
        .preferredColorScheme(.dark)
        .task { await play() }
    }

    private func time(at date: Date) -> Double {
        if let frozen = IntroDebug.time { return frozen }
        if finished { return Beat.end }
        guard let start else { return 0 }
        return min(date.timeIntervalSince(start), Beat.end)
    }

    private func play() async {
        guard IntroDebug.time == nil else { return }
        if reduceMotion {
            // No spinning iris or moving letters: the finished screen fades in instead
            withAnimation(.easeOut(duration: 0.5)) { finished = true }
            return
        }
        sounds.prepare()
        start = Date()
        try? await Task.sleep(nanoseconds: UInt64(Beat.open.lowerBound * 1e9))
        sounds.playOpen()
        try? await Task.sleep(nanoseconds: UInt64((Beat.open.upperBound - Beat.open.lowerBound - 0.05) * 1e9))
        HapticFeedback.impact(.medium)
        try? await Task.sleep(nanoseconds: UInt64((Beat.end - Beat.open.upperBound + 0.05) * 1e9))
        finished = true
    }

    // MARK: - One frame

    @ViewBuilder
    private func frame(at t: Double) -> some View {
        let open = Ease.iris(Beat.open.progress(t))
        let focus = Ease.out(Beat.focus.progress(t))
        ZStack {
            Color.black.ignoresSafeArea()

            if t >= Beat.open.lowerBound {
                photoLayer(open: open, focus: focus)
                    .ignoresSafeArea()
            }

            // Darkens the bottom for the words, only once the lens has gone
            LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0),
                                   .init(color: .clear, location: 0.15),
                                   .init(color: .clear, location: 0.46),
                                   .init(color: .black.opacity(0.72), location: 0.64),
                                   .init(color: .black.opacity(0.94), location: 0.82),
                                   .init(color: .black, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .opacity(Ease.inOut(Beat.scrim.progress(t)))
                .ignoresSafeArea()
                .allowsHitTesting(false)

            words(at: t)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

            if open < 1 {
                LensView(open: open,
                         centerY: lerp(0.47, photo.eyes, Ease.inOut(open)),
                         grip: 0.1 * Ease.inOut(Beat.glint.progress(t)) + 0.32 * open,
                         glint: Beat.glint.progress(t))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // The lens comes up out of black
            Color.black
                .opacity(1 - Ease.out(Beat.lensIn.progress(t)))
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    /// The photo behind the lens: a touch too close, dark and out of focus at first, then it settles
    /// sharp, like a camera finding focus and exposure.
    private func photoLayer(open: Double, focus: Double) -> some View {
        GeometryReader { geo in
            let shownWidth = geo.size.height * photo.aspect
            let slide = max(0, shownWidth - geo.size.width) * (0.5 - photo.faceX)
            Image(photo.asset)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .offset(x: slide)
                .scaleEffect(1.14 - 0.14 * Ease.out(open), anchor: UnitPoint(x: 0.5, y: photo.eyes))
                .blur(radius: 6 * (1 - focus), opaque: true)
                .brightness(-0.08 * (1 - focus))
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
    }

    private func words(at t: Double) -> some View {
        let logo = Ease.out(Beat.logo.progress(t))
        let welcome = Ease.out(Beat.welcome.progress(t))
        let line = Ease.out(Beat.line.progress(t))
        let button = Ease.out(Beat.button.progress(t))
        return VStack(spacing: 0) {
            Spacer()
            Image("app-logo")
                .resizable()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                .blur(radius: 8 * (1 - logo))
                .opacity(logo)
                .offset(y: 14 * (1 - logo))

            Text("Welcome to")
                .font(.app(20, weight: .semibold))
                .foregroundColor(.white.opacity(0.82))
                .shadow(color: .black.opacity(0.45), radius: 6)
                .blur(radius: 6 * (1 - welcome))
                .opacity(welcome)
                .offset(y: 10 * (1 - welcome))
                .padding(.top, 24)

            TitleView(style: style, t: t)
                .shadow(color: .black.opacity(0.45), radius: 8)
                .padding(.top, style.gapAbove)

            Text("Smoother skin and film looks,\nright in your camera.")
                .font(.app(17, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.5), radius: 4)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 16)
                .opacity(line)
                .offset(y: 12 * (1 - line))

            Button {
                HapticFeedback.impact()
                onContinue()
            } label: {
                HStack(spacing: 8) {
                    Text("Get started")
                    Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
                }
                .font(.app(18, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.white, in: Capsule())
            }
            .padding(.top, 38)
            .opacity(button)
            .offset(y: 12 * (1 - button))
            .disabled(t < Beat.button.lowerBound)
        }
    }
}

// MARK: - Timing (seconds from when the screen appears)

private enum Beat {
    static let lensIn = 0.0...0.45      // lens fades up from black
    static let glint = 0.25...0.95      // light slides across the glass, focus ring turns a little
    static let open = 0.85...2.35       // iris opens and the view moves through the lens
    static let focus = 1.3...2.7        // photo comes into focus
    static let scrim = 2.1...2.8
    static let logo = 2.3...2.85
    static let welcome = 2.5...3.0
    static let titleStart = 2.62
    static let letterGap = 0.065
    static let letterLength = 0.6
    static let tracking = 2.62...3.6   // letters drift from wide apart to their final spacing
    static let shine = 3.7...4.5        // one warm light sweep across the name
    static let line = 3.35...3.85
    static let button = 3.6...4.1
    static let end = 4.6

    /// Letters come in from the middle of the name outward
    static func letter(_ i: Int, of count: Int) -> ClosedRange<Double> {
        let fromMiddle = abs(Double(i) - Double(count - 1) / 2)
        let s = titleStart + fromMiddle * letterGap * 1.2
        return s...(s + letterLength)
    }
}

private extension ClosedRange where Bound == Double {
    func progress(_ t: Double) -> Double { Swift.min(Swift.max((t - lowerBound) / (upperBound - lowerBound), 0), 1) }
}

private func lerp(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * f }

private enum Ease {
    static func out(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func inOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    /// Slow first movement, quick middle, soft mechanical stop
    static func iris(_ x: Double) -> Double { bezier(x, 0.55, 0, 0.12, 1) }

    static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var u = x
        for _ in 0..<10 {
            let xu = 3 * (1 - u) * (1 - u) * u * x1 + 3 * (1 - u) * u * u * x2 + u * u * u - x
            let dx = 3 * (1 - u) * (1 - u) * x1 + 6 * (1 - u) * u * (x2 - x1) + 3 * u * u * (1 - x2)
            if abs(dx) < 1e-6 { break }
            u = Swift.min(Swift.max(u - xu / dx, 0), 1)
        }
        return 3 * (1 - u) * (1 - u) * u * y1 + 3 * (1 - u) * u * u * y2 + u * u * u
    }
}

// MARK: - Photo and title choices

private struct IntroPhoto {
    let asset: String
    let aspect: Double   // width / height of the picture
    let eyes: Double     // how far down the eyes are, 0 = top, 1 = bottom
    let faceX: Double    // where the face is across, 0.5 = middle

    static let all: [IntroPhoto] = [
        // Unsplash License photo (free for commercial use) by Hamed Farahpour; picked by the user 2026-11-19
        IntroPhoto(asset: "intro-photo-a", aspect: 1600 / 2399, eyes: 0.32, faceX: 0.5),
    ]

    static var current: IntroPhoto {
        let i = IntroDebug.photo
        return all.indices.contains(i - 1) ? all[i - 1] : all[0]
    }
}

private enum TitleStyle: Int {
    case expanded = 1, futura, compressed, didot, bricolage

    static var current: TitleStyle { TitleStyle(rawValue: IntroDebug.font) ?? .bricolage }   // user picked E

    var text: String {
        switch self {
        case .didot, .bricolage: return "CinematiCam"
        default: return "CINEMATICAM"
        }
    }

    var font: Font {
        switch self {
        case .expanded: return .system(size: 31, weight: .black, design: .default).width(.expanded)
        case .futura: return .custom("Futura-Bold", size: 35)
        case .compressed: return .system(size: 70, weight: .black).width(.compressed)
        case .didot: return .custom("Didot-Bold", size: 50)
        case .bricolage: return .app(50, weight: .heavy)
        }
    }

    /// Space between letters at rest, and how far apart they start
    var tracking: CGFloat {
        switch self {
        case .expanded: return 1.5
        case .futura: return 3
        case .compressed: return 1
        case .didot: return 0
        case .bricolage: return -1.5
        }
    }

    var startTracking: CGFloat { tracking + 9 }

    var gapAbove: CGFloat {
        switch self {
        case .compressed: return 0
        case .didot, .bricolage: return 0
        default: return 6
        }
    }
}

private enum IntroDebug {
    #if DEBUG
    static let time: Double? = UserDefaults.standard.object(forKey: "introTime") == nil
        ? nil : UserDefaults.standard.double(forKey: "introTime")
    static let photo = UserDefaults.standard.integer(forKey: "introPhoto")
    static let font = UserDefaults.standard.integer(forKey: "introFont")
    #else
    static let time: Double? = nil
    static let photo = 0
    static let font = 0
    #endif
}

/// The app name: each letter starts soft and low and comes into focus in turn while the
/// letters draw together, then one warm light passes across it.
private struct TitleView: View {
    let style: TitleStyle
    let t: Double

    var body: some View {
        let letters = Array(style.text)
        let spacing = style.tracking + (style.startTracking - style.tracking) * (1 - Ease.out(Beat.tracking.progress(t)))
        let shine = Beat.shine.progress(t)
        letterRow(letters, spacing: spacing, finished: false)
            .overlay {
                if shine > 0 && shine < 1 {
                    let x = -0.4 + 1.8 * Ease.inOut(shine)
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: Color(red: 1, green: 0.86, blue: 0.5), location: 0.5),
                                           .init(color: .clear, location: 1)],
                                   startPoint: UnitPoint(x: x - 0.22, y: 0.2),
                                   endPoint: UnitPoint(x: x + 0.22, y: 0.8))
                        .mask(letterRow(letters, spacing: spacing, finished: true))
                }
            }
            .fixedSize()
    }

    private func letterRow(_ letters: [Character], spacing: CGFloat, finished: Bool) -> some View {
        HStack(spacing: spacing) {
            ForEach(letters.indices, id: \.self) { i in
                let p = finished ? 1 : Ease.out(Beat.letter(i, of: letters.count).progress(t))
                Text(String(letters[i]))
                    .font(style.font)
                    .foregroundColor(.white)
                    .blur(radius: 11 * (1 - p))
                    .opacity(p)
                    .offset(y: 16 * (1 - p))
            }
        }
    }
}

// MARK: - Sound

/// Plays the iris sound (made in code by cook/sfx). Ambient, so the silent switch mutes it.
private final class ShutterSounds {
    private var open: AVAudioPlayer?

    func prepare() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
        open = load("shutter-open")
    }

    func playOpen() { open?.play() }

    private func load(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.volume = 0.9
        player.prepareToPlay()
        return player
    }
}

// MARK: - The lens

private struct LensView: View {
    var open: Double     // 0 = iris shut, 1 = fully open and the lens is past the screen
    var centerY: Double  // where the iris sits, as a share of the screen height
    var grip: Double     // turn of the ribbed focus ring, radians
    var glint: Double    // 0...1 light sliding across the glass

    var body: some View {
        Canvas { context, size in
            LensPainter(size: size, open: open, centerY: centerY, grip: grip, glint: glint).draw(context)
        }
        .drawingGroup()
    }
}

/// Draws the lens front: 12 curved iris blades, the glass over them, and the barrel around them
/// with its engraving and ribbed focus ring. As the iris opens the whole lens grows past the
/// screen edges, as if the camera moves through it.
private struct LensPainter {
    let size: CGSize
    let open: Double
    let centerY: Double
    let grip: Double
    let glint: Double

    static let blades = 12
    static let light = -2.25                 // light comes from the upper left
    static let accent = Color(red: 1, green: 0.84, blue: 0.04)

    func draw(_ context: GraphicsContext) {
        let w = size.width, h = size.height
        let c = CGPoint(x: w / 2, y: h * centerY)
        let far = [CGPoint.zero, CGPoint(x: w, y: 0), CGPoint(x: 0, y: h), CGPoint(x: w, y: h)]
            .map { hypot($0.x - c.x, $0.y - c.y) }.max() ?? h
        let e = open
        let hole = far * 1.08 * pow(e, 1.3)          // corner distance of the opening
        guard hole < far * 1.07 else { return }
        let r0 = w * 0.33                             // glass radius at rest
        let glassR = r0 + far * 2.4 * e * e
        let zoom = glassR / r0
        let n = Self.blades
        let step = 2 * Double.pi / Double(n)
        let turn = -Double.pi / 2 + 0.95 * (1 - e)

        func at(_ angle: Double, _ radius: Double) -> CGPoint {
            CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
        }

        let corners = (0..<n).map { at(turn + Double($0) * step, hole) }

        // Each blade edge leaves a corner of the opening along that side's line, then bends
        // outward to the rim, which gives the swirl of a real iris.
        let rimR = glassR + 6
        let edges: [[CGPoint]] = (0..<n).map { k in
            var p = corners[k]
            var dir = turn + Double(k) * step - step / 2 + Double.pi / 2
            let ds = rimR / 46
            let bend = 0.75 / rimR
            var pts = [p]
            for _ in 0..<400 {
                p = CGPoint(x: p.x + cos(dir) * ds, y: p.y + sin(dir) * ds)
                dir -= bend * ds
                pts.append(p)
                if hypot(p.x - c.x, p.y - c.y) >= rimR { break }
            }
            return pts
        }

        func bladePath(_ k: Int) -> Path {
            let next = (k + 1) % n
            var path = Path()
            path.move(to: corners[k])
            path.addLine(to: corners[next])
            for p in edges[next].dropFirst() { path.addLine(to: p) }
            // back round the rim to the end of this blade's other edge
            let a0 = atan2(edges[next].last!.y - c.y, edges[next].last!.x - c.x)
            var a1 = atan2(edges[k].last!.y - c.y, edges[k].last!.x - c.x)
            while a1 > a0 { a1 -= 2 * Double.pi }
            while a1 < a0 - 2 * Double.pi { a1 += 2 * Double.pi }
            for j in 1...8 { path.addLine(to: at(a0 + (a1 - a0) * Double(j) / 8, rimR + 2)) }
            for p in edges[k].reversed() { path.addLine(to: p) }
            path.closeSubpath()
            return path
        }

        var holePath = Path()
        if hole > 0.5 { holePath.addLines(corners); holePath.closeSubpath() }
        let screen = Path(CGRect(origin: .zero, size: size))

        // 1. Black everywhere but the opening, so no photo leaks between blades
        var around = screen
        around.addPath(holePath)
        context.fill(around, with: .color(.black), style: FillStyle(eoFill: true))

        // 2. Blades: dark anodised metal; each catches the light a little differently
        let shadowScale = min(zoom, 3)
        for k in 0..<n {
            let path = bladePath(k)
            let mid = turn + (Double(k) + 0.5) * step + 0.5
            let lit = 0.5 + 0.5 * cos(mid - Self.light)
            let tone = 0.035 + 0.09 * lit
            let inner = CGPoint(x: (corners[k].x + corners[(k + 1) % n].x) / 2,
                                y: (corners[k].y + corners[(k + 1) % n].y) / 2)
            context.fill(path, with: .linearGradient(
                Gradient(colors: [Color(red: tone * 1.75, green: tone * 1.8, blue: tone * 1.95),
                                  Color(red: tone * 0.95, green: tone, blue: tone * 1.1),
                                  Color(white: tone * 0.45)]),
                startPoint: inner, endPoint: at(mid, rimR)))
        }

        // 3. Soft shadow each blade throws on the one beneath it, along its outer edge
        for k in 0..<n {
            var shade = context
            shade.clip(to: bladePath(k))
            let edgePath = Path { p in p.addLines(edges[k]) }
            for (width, alpha) in [(22.0, 0.2), (12.0, 0.28), (4.0, 0.42)] {
                shade.stroke(edgePath, with: .color(.black.opacity(alpha)), lineWidth: width * shadowScale)
            }
        }

        // 4. Light catching each blade's edge: brightest at the opening, fading toward the rim
        for k in 0..<n {
            let prev = (k + n - 1) % n
            var edgePath = Path()
            edgePath.move(to: corners[prev])
            edgePath.addLine(to: corners[k])
            for p in edges[k].dropFirst() { edgePath.addLine(to: p) }
            let face = 0.5 + 0.5 * cos(turn + Double(k) * step - Self.light)
            context.stroke(edgePath, with: .radialGradient(
                Gradient(colors: [.white.opacity(0.22 + 0.33 * face), .white.opacity(0.04)]),
                center: c, startRadius: hole, endRadius: rimR),
                lineWidth: 1.3)
        }

        // 5. A broad soft light that swings across the blades as they turn
        var sheen = context
        sheen.clip(to: around, style: FillStyle(eoFill: true))
        sheen.blendMode = .plusLighter
        let swing = Self.light + 0.4 + 1.5 * e
        sheen.fill(screen, with: .radialGradient(
            Gradient(colors: [.white.opacity(0.09), .clear]),
            center: at(swing, glassR * 0.55), startRadius: 0, endRadius: glassR * 0.9))

        // 6. Rim of the opening
        if hole > 1.5 {
            context.stroke(holePath, with: .color(.black.opacity(0.6)), lineWidth: 3)
            context.stroke(holePath, with: .color(.white.opacity(0.22)), lineWidth: 0.8)
        }

        // 7. The glass over the iris: deeper toward its edge, with a soft window reflection
        let glassFade = 1 - min(e / 0.45, 1)
        let glassCircle = Path(ellipseIn: CGRect(x: c.x - glassR, y: c.y - glassR, width: glassR * 2, height: glassR * 2))
        if glassFade > 0 {
            var glass = context
            glass.clip(to: glassCircle)
            glass.opacity = glassFade
            glass.fill(glassCircle, with: .radialGradient(
                Gradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.55),
                                 .init(color: .black.opacity(0.45), location: 1)]),
                center: c, startRadius: 0, endRadius: glassR))

            var window = glass
            window.blendMode = .plusLighter
            window.translateBy(x: c.x - glassR * 0.34, y: c.y - glassR * 0.4)
            window.rotate(by: .radians(-0.62))
            let ew = glassR * 0.95, eh = glassR * 0.36
            window.fill(Path(ellipseIn: CGRect(x: -ew / 2, y: -eh / 2, width: ew, height: eh)),
                        with: .radialGradient(Gradient(colors: [Color(red: 0.78, green: 0.84, blue: 1).opacity(0.09), .clear]),
                                              center: .zero, startRadius: 0, endRadius: ew / 2))

            // a band of light slides across the glass once while the lens waits
            if glint > 0 && glint < 1 {
                var band = glass
                band.blendMode = .plusLighter
                let x = -1.3 + 2.6 * Ease.inOut(glint)
                band.fill(glassCircle, with: .linearGradient(
                    Gradient(stops: [.init(color: .clear, location: 0),
                                     .init(color: .white.opacity(0.13), location: 0.5),
                                     .init(color: .clear, location: 1)]),
                    startPoint: CGPoint(x: c.x + (x - 0.35) * glassR, y: c.y - glassR),
                    endPoint: CGPoint(x: c.x + (x + 0.35) * glassR, y: c.y + glassR)))
            }
        }

        // 8. The barrel: a lit lip, the engraved face, the ribbed focus ring
        let lipOut = glassR + 6 * zoom
        let faceOut = glassR + 31 * zoom
        let gripOut = glassR + 54 * zoom
        guard glassR < far * 1.6 else { return }

        func ring(_ inner: Double, _ outer: Double) -> Path {
            var p = Path(ellipseIn: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
            p.addPath(Path(ellipseIn: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2)))
            return p
        }
        let eo = FillStyle(eoFill: true)
        // lit from above: bright at the top, dark below
        let litTop = Gradient(stops: [.init(color: Color(white: 0.16), location: 0),
                                      .init(color: Color(white: 0.05), location: 0.25),
                                      .init(color: Color(white: 0.16), location: 0.5),
                                      .init(color: Color(white: 0.36), location: 0.75),
                                      .init(color: Color(white: 0.16), location: 1)])
        context.fill(ring(glassR, lipOut), with: .conicGradient(litTop, center: c), style: eo)
        context.stroke(Path(ellipseIn: CGRect(x: c.x - glassR, y: c.y - glassR, width: glassR * 2, height: glassR * 2)),
                       with: .color(.black.opacity(0.8)), lineWidth: 1.5)

        let faceTone = Gradient(stops: [.init(color: Color(white: 0.06), location: 0),
                                        .init(color: Color(white: 0.035), location: 0.25),
                                        .init(color: Color(white: 0.06), location: 0.5),
                                        .init(color: Color(white: 0.11), location: 0.75),
                                        .init(color: Color(white: 0.06), location: 1)])
        context.fill(ring(lipOut, faceOut), with: .conicGradient(faceTone, center: c), style: eo)
        // thin yellow line round the glass, like the coloured ring on cinema lenses
        let accentR = lipOut + 1.5 * zoom
        context.stroke(Path(ellipseIn: CGRect(x: c.x - accentR, y: c.y - accentR, width: accentR * 2, height: accentR * 2)),
                       with: .conicGradient(Gradient(stops: [
                           .init(color: Color(red: 0.55, green: 0.42, blue: 0.1), location: 0),
                           .init(color: Color(red: 0.4, green: 0.3, blue: 0.06), location: 0.25),
                           .init(color: Color(red: 0.55, green: 0.42, blue: 0.1), location: 0.5),
                           .init(color: Color(red: 1, green: 0.88, blue: 0.45), location: 0.75),
                           .init(color: Color(red: 0.55, green: 0.42, blue: 0.1), location: 1)]), center: c),
                       lineWidth: 1.6 * min(zoom, 2))

        // engraving
        if zoom < 2.6 {
            let textR = (lipOut + faceOut) / 2 + 1 * zoom
            let font = Font.system(size: 10.5 * zoom, weight: .semibold).width(.expanded)
            arcText("CINEMATICAM   CINE LENS   35mm  1:1.4", in: context, center: c, radius: textR + 2 * zoom,
                    upper: true, font: font, color: .white.opacity(0.88), spacing: 1.5 * zoom)
            arcText("\u{2300}77mm   0.25m / 0.8ft", in: context, center: c, radius: textR - 2 * zoom,
                    upper: false, font: font, color: .white.opacity(0.7), spacing: 1.5 * zoom)
        }

        // ribbed rubber focus ring
        context.fill(ring(faceOut, gripOut), with: .color(Color(white: 0.035)), style: eo)
        let ribs = 150
        for i in 0..<ribs {
            let a = grip + Double(i) / Double(ribs) * 2 * Double.pi
            let lit = 0.5 + 0.5 * cos(a + Double.pi / 2)    // top of the ring catches the light
            var rib = Path()
            rib.move(to: at(a, faceOut + 3 * zoom))
            rib.addLine(to: at(a, gripOut - 3 * zoom))
            context.stroke(rib, with: .color(.white.opacity(0.04 + 0.13 * lit * lit)), lineWidth: 1.3 * min(zoom, 2.5))
        }
        context.stroke(Path(ellipseIn: CGRect(x: c.x - faceOut, y: c.y - faceOut, width: faceOut * 2, height: faceOut * 2)),
                       with: .color(.white.opacity(0.1)), lineWidth: 1)
        context.stroke(Path(ellipseIn: CGRect(x: c.x - gripOut, y: c.y - gripOut, width: gripOut * 2, height: gripOut * 2)),
                       with: .color(.white.opacity(0.14)), lineWidth: 1)
    }

    /// Letters set round a circle: along the top reading clockwise, along the bottom reading left to right.
    private func arcText(_ text: String, in context: GraphicsContext, center c: CGPoint, radius: Double,
                         upper: Bool, font: Font, color: Color, spacing: Double) {
        let glyphs = text.map { context.resolve(Text(String($0)).font(font).foregroundColor(color)) }
        let widths = glyphs.map { Double($0.measure(in: CGSize(width: 400, height: 400)).width) }
        let total = widths.reduce(0, +) + spacing * Double(max(glyphs.count - 1, 0))
        var x = 0.0
        for (g, wd) in zip(glyphs, widths) {
            let along = (x + wd / 2 - total / 2) / radius
            let angle = upper ? -Double.pi / 2 + along : Double.pi / 2 - along
            var gc = context
            gc.translateBy(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
            gc.rotate(by: .radians(upper ? angle + Double.pi / 2 : angle - Double.pi / 2))
            gc.draw(g, at: .zero, anchor: .center)
            x += wd + spacing
        }
    }
}
