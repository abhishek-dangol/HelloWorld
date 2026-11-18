import SwiftUI

/// Centre of the shutter row while a video is being recorded: the white ring with a red
/// dot and "REC" that blink together. While paused the dot and the word "PAUSED" hold still.
/// It is a sign, not a button: Pause sits on its left and End on its right.
struct RecordingIndicator: View {
    let isPaused: Bool
    @State private var dimmed = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 4)
                .frame(width: 74, height: 74)
            VStack(spacing: 3) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 22, height: 22)
                Text(isPaused ? "PAUSED" : "REC")
                    .font(.system(size: isPaused ? 10 : 13, weight: .bold))
                    .foregroundColor(isPaused ? .white : .red)
            }
            // Blink by fading only (never by resizing, which looks pixelated)
            .opacity(isPaused ? 0.55 : (dimmed ? 0.2 : 1))
            .turnsWithPhone()
        }
        .frame(width: 80, height: 80)
        .onAppear { startBlink() }
        .onChange(of: isPaused) { _ in startBlink() }
        .accessibilityLabel(isPaused ? "Recording paused" : "Recording")
    }

    private func startBlink() {
        dimmed = false
        guard !isPaused else { return }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            dimmed = true
        }
    }
}

/// Solid white round button with its name underneath (Pause, Resume, End).
struct LabeledRecordingButton<Icon: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button {
            HapticFeedback.impact()
            action()
        } label: {
            VStack(spacing: 4) {
                icon()
                    .frame(width: 54, height: 54)
                    .background(Color.white, in: Circle())
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
            }
            .turnsWithPhone()
        }
        .accessibilityLabel(title)
    }
}

/// Round picture of the last photo or clip, left of the shutter. With `popIn` it grows
/// from a dot to full size with a soft tap, the way the iPhone Camera shows that a
/// video was just saved.
struct SavedThumbnail: View {
    let image: UIImage
    let popIn: Bool
    let onPopFinished: () -> Void
    @State private var grown = true

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
            .scaleEffect(grown ? 1 : 0.15)
            .opacity(grown ? 1 : 0)
            .turnsWithPhone()
            .onAppear {
                guard popIn else { return }
                grown = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { grown = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onPopFinished() }
            }
    }
}

/// The words shown in the middle of the screen once a video is in Photos.
struct SavedMessage: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.green)
            Text("Video Saved")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        .background(Color.black.opacity(0.75), in: Capsule())
        .turnsWithPhone()
        .accessibilityLabel("Video saved to Photos")
    }
}
