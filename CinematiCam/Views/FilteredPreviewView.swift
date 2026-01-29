import SwiftUI
import UIKit

struct FilteredPreviewView: View {
    let image: UIImage?

    var body: some View {
        GeometryReader { _ in
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
    }
}
