import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct FilterThumbnailView: View {
    let filter: Filter
    let isSelected: Bool

    private static let ciContext = CIContext()
    private static var sampleImage: CIImage = {
        // Load sample image from assets
        if let uiImage = UIImage(named: "FilterSample"),
           let cgImage = uiImage.cgImage {
            // Thumbnails are drawn about 112 points wide, so 340 pixels is plenty
            let scale = 340 / CGFloat(cgImage.width)
            return CIImage(cgImage: cgImage).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        // Fallback to gradient if image not found
        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: 0, y: 0)
        gradient.point1 = CGPoint(x: 100, y: 100)
        gradient.color0 = CIColor(red: 1.0, green: 0.8, blue: 0.6)
        gradient.color1 = CIColor(red: 0.4, green: 0.6, blue: 0.8)
        return gradient.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100)) ?? CIImage()
    }()

    var body: some View {
        VStack(spacing: 4) {
            filteredImage
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 3)
                )

            Text(filter.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .yellow : .white)
        }
    }

    /// Each filter's thumbnail is drawn once and kept, so the row stays smooth with many filters.
    private static var thumbnails: [String: UIImage] = [:]

    private static func thumbnail(for filter: Filter) -> UIImage? {
        if let saved = thumbnails[filter.name] { return saved }
        let filtered = filter.apply(to: sampleImage)
        guard let cgImage = ciContext.createCGImage(filtered, from: filtered.extent) else { return nil }
        let image = UIImage(cgImage: cgImage)
        thumbnails[filter.name] = image
        return image
    }

    private var filteredImage: some View {
        if let thumbnail = Self.thumbnail(for: filter) {
            return AnyView(
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 112, height: 112)
                    .offset(y: 14)
            )
        }
        return AnyView(
            Image(uiImage: UIImage())
                .resizable()
                .aspectRatio(contentMode: .fill)
        )
    }
}
