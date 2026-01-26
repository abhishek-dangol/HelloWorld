import CoreImage

struct CoolFilter: Filter {

    let name = "Cool"

    func apply(to image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CITemperatureAndTint") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        // Neutral is 6500K, lower = cooler. 4500K gives noticeable cool tones
        filter.setValue(CIVector(x: 4500, y: 0), forKey: "inputNeutral")
        // Target temperature
        filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")

        return filter.outputImage ?? image
    }
}
