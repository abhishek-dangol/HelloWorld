import CoreImage
import AVFoundation

class BokehRenderer {

    private var hasLoggedReady = false

    init() {
        print("Renderer ready")
    }

    func render(videoBuffer: CMSampleBuffer, mask: CIImage, blurRadius: Float) -> CIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(videoBuffer) else {
            return nil
        }

        var videoImage = CIImage(cvPixelBuffer: pixelBuffer)
        videoImage = videoImage.oriented(.right)

        let scaleX = videoImage.extent.width / mask.extent.width
        let scaleY = videoImage.extent.height / mask.extent.height
        var scaledMask = mask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        scaledMask = scaledMask.transformed(by: CGAffineTransform(translationX: videoImage.extent.origin.x, y: videoImage.extent.origin.y))

        let blurredImage = videoImage.applyingFilter("CIMaskedVariableBlur", parameters: [
            "inputMask": scaledMask,
            "inputRadius": blurRadius
        ])

        if !hasLoggedReady {
            print("Bokeh applied")
            hasLoggedReady = true
        }

        return blurredImage
    }
}
