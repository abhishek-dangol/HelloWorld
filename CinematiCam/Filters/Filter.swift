import CoreImage

protocol Filter {
    var name: String { get }
    func apply(to image: CIImage) -> CIImage
}
