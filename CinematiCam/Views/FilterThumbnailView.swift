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
            return CIImage(cgImage: cgImage)
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
                .frame(width: 50, height: 50)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 3)
                )

            Text(filter.name)
                .font(.system(size: 10))
                .foregroundColor(isSelected ? .yellow : .white)
        }
    }

    private var filteredImage: some View {
        let filtered = filter.apply(to: Self.sampleImage)
        if let cgImage = Self.ciContext.createCGImage(filtered, from: filtered.extent) {
            return AnyView(
                Image(uiImage: UIImage(cgImage: cgImage))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .offset(y: 10)
            )
        }
        return AnyView(
            Image(uiImage: UIImage())
                .resizable()
                .aspectRatio(contentMode: .fill)
        )
    }
}
