import SwiftUI

/// The welcome screens shown once, the first time the app opens. The camera screen (and its
/// camera, microphone and Photos questions) only appears after the last page.
/// Pictures: a free Pexels stock photo run through the app's own skin smoothing, looks and Mist.
/// Type: Bricolage Grotesque, the same font as the DoomLess app.
struct WelcomeView: View {
    var onFinish: () -> Void
    @State private var page = WelcomeView.firstPage
    /// The logo-and-shutter screen comes first
    @State private var showIntro = WelcomeView.startsWithIntro
    private let pageCount = 5

    /// Test builds can open a later page with the launch argument `-welcomePage N`,
    /// and skip the shutter screen with `-skipIntro YES`
    private static var firstPage: Int {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "welcomePage")
        #else
        return 0
        #endif
    }
    private static var startsWithIntro: Bool {
        #if DEBUG
        return firstPage == 0 && !UserDefaults.standard.bool(forKey: "skipIntro")
        #else
        return true
        #endif
    }

    var body: some View {
        ZStack {
            if showIntro {
                ShutterIntroView {
                    withAnimation(.easeInOut(duration: 0.4)) { showIntro = false }
                }
                .transition(.opacity)
            } else {
                pages.transition(.opacity)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { Diagnostics.log("App", "Welcome shown") }
    }

    private var isLast: Bool { page == pageCount - 1 }

    private var pages: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            TabView(selection: $page) {
                SmoothingPage(active: page == 0).tag(0)
                StrengthPage(active: page == 1).tag(1)
                LooksPage(active: page == 2).tag(2)
                ToolsPage(active: page == 3).tag(3)
                AccessPage(active: page == 4).tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack(spacing: 18) {
                // How far along: one bar per page, the current one filled
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Capsule()
                            .fill(i <= page ? Color.white : Color.white.opacity(0.3))
                            .frame(height: 4)
                    }
                }
                .animation(.spring(duration: 0.4, bounce: 0), value: page)

                Button {
                    HapticFeedback.impact(.light)
                    if isLast {
                        Diagnostics.log("App", "Welcome finished")
                        onFinish()
                    } else {
                        withAnimation(.spring(duration: 0.45, bounce: 0)) { page += 1 }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(isLast ? "Allow and start" : "Continue")
                        if !isLast { Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold)) }
                    }
                    .font(.app(18, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(isLast ? Welcome.accent : Color.white, in: Capsule())
                    .contentTransition(.opacity)
                }
                .buttonStyle(PressStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
        .overlay(alignment: .topTrailing) {
            if page < pageCount - 1 {
                Button("Skip") {
                    Diagnostics.log("App", "Welcome skipped on page \(page + 1)")
                    withAnimation(.spring(duration: 0.45, bounce: 0)) { page = pageCount - 1 }
                }
                .font(.app(16, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.trailing, 20)
                .padding(.top, 6)
            }
        }
    }
}

private enum Welcome {
    static let accent = Color(red: 1, green: 0.84, blue: 0.04)
    static let card = Color.white.opacity(0.1)
    static let cardEdge = Color.white.opacity(0.13)
    static let spring = Animation.spring(duration: 0.6, bounce: 0.12)
    /// The picture at the top of pages 2-5, the same size on each so swiping between them stays steady
    static let heroHeight: CGFloat = 290
}

// MARK: - Pages

/// Page 1: the main reason to get the app, as a drag-to-compare before and after
private struct SmoothingPage: View {
    let active: Bool
    var body: some View {
        ZStack(alignment: .bottom) {
            CompareView(before: "welcome-before", after: "welcome-after",
                        beforeLabel: "Before", afterLabel: "After", showVideoBadge: true, hintWhen: active)
                .ignoresSafeArea()
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black.opacity(0.8), location: 0.32),
                                   .init(color: .black, location: 0.7)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 490)
                .allowsHitTesting(false)
            PageText(title: "Smoother skin, right in your videos", bottomSpace: 160, active: active) {
                VStack(alignment: .leading, spacing: 10) {
                    Tick("The iPhone Camera can't do this in video.").reveal(active, 2)
                    Tick("Keep it light and people can hardly tell it's on.").reveal(active, 3)
                    Tick("No plastic TikTok or Instagram look.").reveal(active, 4)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

/// Page 2: one big face whose smoothing follows the slider
private struct StrengthPage: View {
    let active: Bool
    @State private var strength = 0.5
    private let stops: [(String, Double)] = [("Off", 0), ("Light", 0.5), ("Strong", 1)]

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .overlay { Image("welcome-off").resizable().scaledToFill() }
                    .overlay { Image("welcome-light").resizable().scaledToFill().opacity(min(strength * 2, 1)) }
                    .overlay { Image("welcome-strong").resizable().scaledToFill().opacity(max(strength * 2 - 1, 0)) }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Welcome.cardEdge, lineWidth: 1))
                HStack(spacing: 7) {
                    Image(systemName: "wand.and.stars").font(.system(size: 13, weight: .semibold))
                    Text("Touch up \(Int((strength * 100).rounded()))%").monospacedDigit()
                }
                .font(.app(15, weight: .semibold))
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(14)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 62)
            .reveal(active, 0)

            StrengthSlider(value: $strength, stops: stops)
                .padding(.horizontal, 30)
                .padding(.top, 20)
                .reveal(active, 1)

            Color.clear.frame(height: 22)
            PageText(title: "You decide how much", active: active, titleDelay: 2) {
                BodyText("Slide it up for a softer look, or down until it's barely there. Eyes, hair and lips stay sharp.")
                    .reveal(active, 3)
            }
        }
    }
}

/// Page 3: the looks and Mist, tried on the same face
private struct LooksPage: View {
    let active: Bool
    @State private var picked = "Film"
    private let looks = ["Natural", "Film", "Golden", "Moody", "Noir", "Mist"]

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .overlay {
                        ZStack {
                            ForEach(looks, id: \.self) { look in
                                Image("welcome-look-\(look.lowercased())").resizable().scaledToFill()
                                    .opacity(look == picked ? 1 : 0)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Welcome.cardEdge, lineWidth: 1))
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 62)
            .reveal(active, 0)

            HStack(spacing: 8) {
                ForEach(looks, id: \.self) { look in
                    let on = look == picked
                    Button {
                        HapticFeedback.impact(.light)
                        withAnimation(.easeInOut(duration: 0.3)) { picked = look }
                    } label: {
                        VStack(spacing: 6) {
                            Image("welcome-look-\(look.lowercased())")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .padding(3)
                                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .stroke(on ? Welcome.accent : .clear, lineWidth: 3))
                            Text(look)
                                .font(.app(13, weight: on ? .bold : .medium))
                                .foregroundColor(on ? .white : .white.opacity(0.72))
                        }
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.top, 14)
            .reveal(active, 1)

            Color.clear.frame(height: 22)
            PageText(title: "Looks and Mist", active: active, titleDelay: 2) {
                BodyText("Tap one to try it. Mist adds a soft, dreamy glow around the light. You see it live before you press record.")
                    .reveal(active, 3)
            }
        }
    }
}

/// Page 4: the other tools, shown on a mock camera screen, then one row each
private struct ToolsPage: View {
    let active: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToolsPicture().reveal(active, 0)
                .padding(.top, 62)
            Spacer(minLength: 16)
            Title("Made for talking to the camera").reveal(active, 1)
            VStack(spacing: 12) {
                Feature("person.and.background.dotted", "Background blur", "A soft background, in photos and video.").reveal(active, 2)
                Feature("text.viewfinder", "Teleprompter", "Your script scrolls while you record.").reveal(active, 3)
                Feature("pause.fill", "Pause and keep going", "Stop and start. It saves as one video.").reveal(active, 4)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 112)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The smoothed face behind a soft blur, with a teleprompter script and a paused recording
private struct ToolsPicture: View {
    var body: some View {
        Color.clear
            .frame(height: Welcome.heroHeight)
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    Image("welcome-after").resizable().scaledToFill().blur(radius: 14)
                    Image("welcome-after").resizable().scaledToFill()
                        .mask(RadialGradient(colors: [.black, .black, .clear], center: UnitPoint(x: 0.5, y: 0.3),
                                             startRadius: 0, endRadius: 210))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .top) {
                Text("Hi everyone! Today I want to show you three things I wish I knew sooner.")
                    .font(.app(17, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(16)
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 7) {
                    Image(systemName: "pause.fill").font(.system(size: 11, weight: .bold))
                    Text("Paused  0:42").monospacedDigit()
                }
                .font(.app(14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(Color.red.opacity(0.85), in: Capsule())
                .padding(16)
            }
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Welcome.cardEdge, lineWidth: 1))
    }
}

/// Page 5: why the app asks for each kind of access, before the iPhone asks
private struct AccessPage: View {
    let active: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AccessPicture().reveal(active, 0)
                .padding(.top, 62)
            Spacer(minLength: 16)
            Title("Allow three things").reveal(active, 1)
            Text("Your iPhone asks next. You can change them later in Settings.")
                .font(.app(16))
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 8)
                .reveal(active, 2)
            VStack(spacing: 12) {
                Feature("camera.fill", "Camera", "To show the picture and take photos and videos.").reveal(active, 3)
                Feature("mic.fill", "Microphone", "To record sound with your videos.").reveal(active, 4)
                Feature("photo.on.rectangle", "Photos", "To save what you take.").reveal(active, 5)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 112)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The app's logo with the three things it asks for around it
private struct AccessPicture: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(RadialGradient(colors: [Color(red: 0.2, green: 0.22, blue: 0.5).opacity(0.55), Welcome.card],
                                     center: .center, startRadius: 10, endRadius: 200))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Welcome.cardEdge, lineWidth: 1))
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 1).frame(width: 190, height: 190)
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 1).frame(width: 290, height: 290)
            Image("app-logo")
                .resizable()
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color(red: 0.3, green: 0.35, blue: 1).opacity(0.5), radius: 24)
            ForEach(Array(["camera.fill", "mic.fill", "photo.on.rectangle"].enumerated()), id: \.offset) { i, icon in
                let angle = -Double.pi / 2 + Double(i) * 2 * .pi / 3
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 48, height: 48)
                    .background(Welcome.accent, in: Circle())
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                    .offset(x: cos(angle) * 95, y: sin(angle) * 95)
            }
        }
        .frame(height: Welcome.heroHeight)
    }
}

/// The touch-up slider: a clear track, a yellow fill, and Off / Light / Strong under their spots
private struct StrengthSlider: View {
    @Binding var value: Double
    let stops: [(String, Double)]

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.28)).frame(height: 5)
                    Capsule().fill(Welcome.accent).frame(width: max(w * value, 5), height: 5)
                    Circle().fill(Color.white)
                        .frame(width: 30, height: 30)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                        .offset(x: w * value - 15)
                }
                .frame(height: 30)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    value = min(max(g.location.x / w, 0), 1)
                })
            }
            .frame(height: 30)

            GeometryReader { geo in
                ForEach(stops, id: \.0) { name, spot in
                    let on = abs(value - spot) < 0.17
                    Button(name) {
                        HapticFeedback.impact(.light)
                        withAnimation(.spring(duration: 0.35, bounce: 0)) { value = spot }
                    }
                    .font(.app(15, weight: on ? .bold : .medium))
                    .foregroundColor(on ? Welcome.accent : .white.opacity(0.62))
                    .fixedSize()
                    .position(x: min(max(geo.size.width * spot, 24), geo.size.width - 24), y: 10)
                }
            }
            .frame(height: 20)
        }
    }
}

// MARK: - Pieces

/// Two pictures on top of each other; the line can be dragged to show more of either.
/// The first time the page shows, the line sweeps once so people see they can drag it.
private struct CompareView: View {
    let before: String, after: String, beforeLabel: String, afterLabel: String
    let showVideoBadge: Bool
    var hintWhen = false
    @State private var split: CGFloat = 0.38
    @State private var hinted = false
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let x = geo.size.width * split
            ZStack(alignment: .topLeading) {
                Image(before).resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
                Image(after).resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
                    .mask(alignment: .trailing) { Rectangle().frame(width: max(geo.size.width - x, 0)) }
                Rectangle().fill(LinearGradient(stops: [.init(color: .white, location: 0),
                                                        .init(color: .white, location: 0.6),
                                                        .init(color: .white.opacity(0), location: 0.7)],
                                                startPoint: .top, endPoint: .bottom))
                    .frame(width: 2, height: geo.size.height)
                    .shadow(color: .black.opacity(0.35), radius: 4)
                    .offset(x: x - 1)
                Image(systemName: "chevron.left.chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: Circle())
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    .offset(x: x - 22, y: geo.size.height * 0.47)
                // Before and After ride along beside the line, just above the handle
                let labelY = geo.size.height * 0.47 - 34
                Chip(beforeLabel)
                    .fixedSize()
                    .frame(width: 120, alignment: .trailing)
                    .offset(x: x - 132, y: labelY)
                    .opacity(x > 110 ? 1 : 0)
                Chip(afterLabel, highlighted: true)
                    .fixedSize()
                    .frame(width: 120, alignment: .leading)
                    .offset(x: x + 12, y: labelY)
                    .opacity(x < geo.size.width - 110 ? 1 : 0)
                if showVideoBadge {
                    HStack(spacing: 7) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text("VIDEO")
                    }
                    .font(.app(13, weight: .bold))
                    .tracking(0.6)
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.leading, 20)
                    .padding(.top, 68)
                }
            }
            .contentShape(Rectangle())
            // Dragging anywhere on the picture moves the line (Continue moves to the next page)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                dragging = true
                split = min(max(value.location.x / geo.size.width, 0.05), 0.95)
            })
        }
        .task(id: hintWhen) {
            guard hintWhen, !hinted else { return }
            hinted = true
            try? await Task.sleep(for: .milliseconds(900))
            guard !dragging else { return }
            withAnimation(.spring(duration: 0.7, bounce: 0)) { split = 0.2 }
            try? await Task.sleep(for: .milliseconds(750))
            guard !dragging else { return }
            withAnimation(.spring(duration: 0.8, bounce: 0)) { split = 0.68 }
            try? await Task.sleep(for: .milliseconds(850))
            guard !dragging else { return }
            withAnimation(.spring(duration: 0.7, bounce: 0.1)) { split = 0.38 }
        }
    }
}

private struct Title: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.app(36, weight: .heavy))
            .tracking(-1.2)
            .lineSpacing(-2)
            .foregroundColor(.white)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PageText<Content: View>: View {
    let title: String
    var bottomSpace: CGFloat = 112
    let active: Bool
    var titleDelay = 1
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Title(title).reveal(active, titleDelay)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, bottomSpace)
    }
}

private struct Chip: View {
    let text: String
    var highlighted = false
    init(_ text: String, highlighted: Bool = false) { self.text = text; self.highlighted = highlighted }
    var body: some View {
        Text(text)
            .font(.app(14, weight: .semibold))
            .foregroundColor(highlighted ? .black : .white)
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background {
                if highlighted { Capsule().fill(Welcome.accent) } else { Capsule().fill(.ultraThinMaterial) }
            }
    }
}

private struct Tick: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(.black)
                .frame(width: 20, height: 20)
                .background(Welcome.accent, in: Circle())
                .padding(.top, 1)
            Text(text)
                .font(.app(16))
                .foregroundColor(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct BodyText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.app(16)).foregroundColor(.white.opacity(0.72)).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Feature: View {
    let icon: String, title: String, detail: String
    init(_ icon: String, _ title: String, _ detail: String) { self.icon = icon; self.title = title; self.detail = detail }
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 48, height: 48)
                .background(LinearGradient(colors: [Welcome.accent, Color(red: 1, green: 0.7, blue: 0.1)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.app(17, weight: .bold))
                Text(detail).font(.app(14)).foregroundColor(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Welcome.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Welcome.cardEdge, lineWidth: 1))
    }
}

/// Buttons dim a little while pressed (no size change)
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Fades and slides a piece in when its page becomes the shown page, one after another by `order`
private struct Reveal: ViewModifier {
    let active: Bool, order: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .onAppear { if active { show() } }
            .onChange(of: active) { now in if now { show() } }
    }
    private func show() {
        guard !shown else { return }
        withAnimation(Welcome.spring.delay(0.06 + Double(order) * 0.08)) { shown = true }
    }
}

private extension View {
    func reveal(_ active: Bool, _ order: Int) -> some View { modifier(Reveal(active: active, order: order)) }
}
