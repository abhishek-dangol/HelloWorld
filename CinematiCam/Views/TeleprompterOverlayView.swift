import SwiftUI

struct TeleprompterOverlayView: View {
    let text: String
    let scrollOffset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let overlayHeight = geometry.size.height * 0.35

            ZStack(alignment: .top) {
                // Semi-transparent background
                Color.black.opacity(0.15)
                    .frame(height: overlayHeight)

                // Text that starts at bottom of overlay and scrolls up
                Text(text)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)
                    // Start text at the bottom of the overlay, scroll upward
                    .offset(y: overlayHeight - 40 - scrollOffset)

                // Fade gradients
                VStack {
                    LinearGradient(
                        colors: [.black.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 30)

                    Spacer()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 30)
                }
                .frame(height: overlayHeight)
            }
            .frame(width: geometry.size.width, height: overlayHeight)
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 90)
        }
        .allowsHitTesting(false)
    }
}
