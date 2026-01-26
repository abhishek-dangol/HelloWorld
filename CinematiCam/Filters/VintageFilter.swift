import CoreImage

struct VintageFilter: Filter {

    let name = "Vintage"

    func apply(to image: CIImage) -> CIImage {
        // Use CIPhotoEffectTransfer for a vintage/retro look
        guard let filter = CIFilter(name: "CIPhotoEffectTransfer") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)

        return filter.outputImage ?? image
    }
}
