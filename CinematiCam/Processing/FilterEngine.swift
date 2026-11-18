import CoreImage

class FilterEngine {

    var selectedFilter: Filter?
    var intensity: Double = 0.8

    init() {
        print("Filter engine ready")
    }

    func applyFilter(to image: CIImage) -> CIImage {
        applyFilter(selectedFilter, intensity: intensity, to: image)
    }

    /// The same with the filter and its strength given by the caller (a photo keeps the
    /// ones from the shutter press)
    func applyFilter(_ filter: Filter?, intensity: Double, to image: CIImage) -> CIImage {
        guard let filter = filter else {
            return image
        }

        let filteredImage = filter.apply(to: image)

        // Blend original and filtered based on intensity
        guard intensity < 1.0 else { return filteredImage }
        guard intensity > 0.0 else { return image }

        // Use CIBlendWithMask or simple dissolve
        guard let blendFilter = CIFilter(name: "CIDissolveTransition") else {
            return filteredImage
        }

        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(filteredImage, forKey: kCIInputTargetImageKey)
        blendFilter.setValue(intensity, forKey: kCIInputTimeKey)

        return blendFilter.outputImage ?? filteredImage
    }
}
