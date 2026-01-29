import SwiftUI

struct TeleprompterOverlayView: View {
    let text: String
    @Binding var scrollOffset: CGFloat
    var onDismiss: () -> Void

    @State private var lastDragValue: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let overlayHeight = geometry.size.height * 0.35
            let overlayWidth = geometry.size.width - 48
            let cornerRadius: CGFloat = 16

            ZStack(alignment: .topLeading) {
                // Masked container: everything outside the rounded rect is invisible
                Color.black.opacity(0.15)
                    .frame(width: overlayWidth, height: overlayHeight)
                    .overlay(alignment: .topLeading) {
                        // Text top edge starts at bottom of overlay (only first line visible)
                        // As scrollOffset increases, text moves up revealing more
                        Text(text)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineSpacing(8)
                            .padding(.horizontal, 20)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: overlayWidth, alignment: .center)
                            .offset(y: overlayHeight - 36 - scrollOffset)
                    }
                    .overlay {
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: [.black.opacity(0.4), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 40)
                            Spacer()
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.4)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 40)
                        }
                    }
                    .mask(RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Dragging up (negative translation) = increase offset (scroll forward)
                                // Dragging down (positive translation) = decrease offset (scroll back)
                                let delta = lastDragValue - value.translation.height
                                scrollOffset = max(0, scrollOffset + delta)
                                lastDragValue = value.translation.height
                            }
                            .onEnded { _ in
                                lastDragValue = 0
                            }
                    )

                // X dismiss button
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .padding(.top, 10)
                .padding(.leading, 10)
            }
            .frame(width: overlayWidth, height: overlayHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 60)
        }
    }
}
