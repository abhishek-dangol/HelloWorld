import CoreImage

struct NaturalFilter: Filter {

    let name = "Natural"

    func apply(to image: CIImage) -> CIImage {
        return image
    }
}
