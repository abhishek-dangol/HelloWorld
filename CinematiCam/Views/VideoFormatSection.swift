import SwiftUI

/// The "Video" rows in Settings: size (4K / 1080p / 720p) and speed (30 / 60) of the camera in use.
///
/// It is its own view on purpose (2026-11-20). Inside the camera screen these rows were rebuilt
/// every time the camera published something (face boxes, tilt, preview: many times a second),
/// with a new hand-made binding each time, so the open list went stale and a tap on "4K" or
/// "1080p" was dropped. Here the rows read the saved settings themselves and are only rebuilt
/// when one of the three plain values below changes.
struct VideoFormatSection: View, Equatable {
    let isFront: Bool
    /// The camera in use can do 60 at the picked size (the selfie camera with blur stops at 30)
    let sixtyAvailable: Bool
    /// Locked while a recording is paused: clips in different formats can't be joined
    let locked: Bool
    /// Called after a pick is saved, so the camera can switch to it
    let changed: () -> Void

    // Each camera remembers its own size and speed (same saved settings as the camera screen)
    @AppStorage("videoQualityBack") private var backQuality = "4K"
    @AppStorage("videoFrameRateBack") private var backFrameRate = 30
    @AppStorage("videoQualityFront") private var frontQuality = "1080p"
    @AppStorage("videoFrameRateFront") private var frontFrameRate = 30

    static func == (a: VideoFormatSection, b: VideoFormatSection) -> Bool {
        a.isFront == b.isFront && a.sixtyAvailable == b.sixtyAvailable && a.locked == b.locked
    }

    var body: some View {
        Section {
            Picker("Quality", selection: isFront ? $frontQuality : $backQuality) {
                Text("4K").tag("4K")
                Text("1080p").tag("1080p")
                Text("720p").tag("720p")
            }
            .onChange(of: isFront ? frontQuality : backQuality) { _ in changed() }
            .disabled(locked)
            if sixtyAvailable {
                Picker("Speed", selection: isFront ? $frontFrameRate : $backFrameRate) {
                    Text("30").tag(30)
                    Text("60").tag(60)
                }
                .onChange(of: isFront ? frontFrameRate : backFrameRate) { _ in changed() }
                .disabled(locked)
            } else {
                // No 60 on this camera at this size: shown as 30 and not changeable
                Picker("Speed", selection: .constant(30)) {
                    Text("30").tag(30)
                    Text("60").tag(60)
                }
                .disabled(true)
            }
        } header: {
            Text(isFront ? "Video (selfie camera)" : "Video (back camera)")
        }
    }
}
