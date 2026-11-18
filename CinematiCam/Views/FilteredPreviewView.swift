import SwiftUI
import UIKit

struct FilteredPreviewView: View {
    let image: UIImage?
    /// true = fill the screen (photo mode). false = show the whole frame with bars
    /// (video mode), so what is on screen is exactly what gets recorded.
    var fillsScreen: Bool = true
    /// When set (width / height) and not filling: show only the centre of the picture in
    /// this shape, fitted on screen. Selfie Photo uses 9:16 so it frames exactly like Video.
    var cropAspect: CGFloat? = nil
    /// Soft blur over the picture while the camera changes between Photo and Video.
    var blurred: Bool = false

    var body: some View {
        GeometryReader { geometry in
            if let image = image {
                // Centre the image so any overflow or bars are equal on both sides
                // (GeometryReader pins children to the top-left otherwise).
                // The black backing hides the full-screen raw preview behind the bars.
                let box = boxSize(in: geometry.size)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fillsScreen || box != nil ? .fill : .fit)
                    .blur(radius: blurred ? 22 : 0)
                    .frame(width: box?.width ?? geometry.size.width,
                           height: box?.height ?? geometry.size.height)
                    .clipped()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(fillsScreen ? Color.clear : Color.black)
                    .clipped()
                    // Blur comes on at once and fades away when the new picture is ready
                    .animation(blurred ? nil : .easeOut(duration: 0.3), value: blurred)
            }
        }
    }

    /// The largest box of `cropAspect` that fits the view; nil when no crop shape is asked for.
    private func boxSize(in size: CGSize) -> CGSize? {
        guard !fillsScreen, let aspect = cropAspect, aspect > 0,
              size.width > 0, size.height > 0 else { return nil }
        return Self.box(aspect: aspect, in: size).size
    }

    /// The largest box of the shape `aspect` (width / height) that fits `size`, centred in it.
    /// Focus taps and the grid use the same box the picture is shown in.
    static func box(aspect: CGFloat, in size: CGSize) -> CGRect {
        let width = min(size.width, size.height * aspect)
        let height = width / aspect
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
}

/// Rule-of-thirds lines over the picture: the whole screen, or (Square and 16:9 photos) the
/// centred box the photo is shown in.
struct ThirdsGrid: View {
    /// Shape of the photo box (width / height); nil = the whole screen
    var aspect: CGFloat? = nil

    var body: some View {
        GeometryReader { geometry in
            let box = aspect.map { FilteredPreviewView.box(aspect: $0, in: geometry.size) }
                ?? CGRect(origin: .zero, size: geometry.size)
            Path { path in
                for step in 1...2 {
                    let x = box.minX + box.width * CGFloat(step) / 3
                    let y = box.minY + box.height * CGFloat(step) / 3
                    path.move(to: CGPoint(x: x, y: box.minY))
                    path.addLine(to: CGPoint(x: x, y: box.maxY))
                    path.move(to: CGPoint(x: box.minX, y: y))
                    path.addLine(to: CGPoint(x: box.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.5), lineWidth: 1)
        }
        .ignoresSafeArea()
    }
}
