import CoreImage

struct BWFilter: Filter {

    let name = "B&W"

    func apply(to image: CIImage) -> CIImage {
        // Use CIPhotoEffectNoir for a classic black & white look
        guard let filter = CIFilter(name: "CIPhotoEffectNoir") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)

        return filter.outputImage ?? image
    }
}
