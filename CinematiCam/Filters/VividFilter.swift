import CoreImage

struct VividFilter: Filter {

    let name = "Vivid"

    func apply(to image: CIImage) -> CIImage {
        // Use CIVibrance to boost colors without oversaturating skin tones
        guard let filter = CIFilter(name: "CIVibrance") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.8, forKey: kCIInputAmountKey)

        return filter.outputImage ?? image
    }
}
