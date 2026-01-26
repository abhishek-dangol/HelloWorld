import AVFoundation
import CoreImage

class DepthMaskGenerator {

    private let ciContext = CIContext()
    private var hasLoggedFirstMask = false

    func generateMask(from depthData: AVDepthData) -> CIImage? {
        let depthMap = depthData.depthDataMap

        // Create CIImage from depth pixel buffer
        let ciImage = CIImage(cvPixelBuffer: depthMap)

        // Normalize depth values: near = white, far = black
        // Depth values are in meters, closer objects have smaller values
        // We invert so that near objects become white (1.0) and far become black (0.0)
        let normalized = ciImage.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 2.0,
            kCIInputBrightnessKey: -0.3
        ])

        // Invert: near (low depth) becomes white, far (high depth) becomes black
        let mask = normalized.applyingFilter("CIColorInvert")

        if !hasLoggedFirstMask {
            print("Mask generated")
            hasLoggedFirstMask = true
        }

        return mask
    }
}
