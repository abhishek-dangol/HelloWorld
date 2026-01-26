import CoreImage

struct WarmFilter: Filter {

    let name = "Warm"

    func apply(to image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CITemperatureAndTint") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        // Neutral is 6500K, higher = warmer. 9000K gives noticeable warmth
        filter.setValue(CIVector(x: 9000, y: 0), forKey: "inputNeutral")
        // Target temperature
        filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")

        return filter.outputImage ?? image
    }
}
