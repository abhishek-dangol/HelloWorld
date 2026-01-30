import AVFoundation
import UIKit

class CaptionRenderer {

    func renderCaptions(videoURL: URL, captions: [CaptionSegment], completion: @escaping (URL?, Error?) -> Void) {
        let asset = AVAsset(url: videoURL)

        Task {
            do {
                let duration = try await asset.load(.duration)
                let tracks = try await asset.loadTracks(withMediaType: .video)

                guard let videoTrack = tracks.first else {
                    completion(nil, NSError(domain: "CaptionRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video track found"]))
                    return
                }

                let naturalSize = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)

                // Determine actual video size after transform
                let transformedSize = naturalSize.applying(transform)
                let size = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

                // Create composition
                let composition = AVMutableComposition()

                guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    completion(nil, NSError(domain: "CaptionRenderer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not create video track"]))
                    return
                }

                try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
                compositionVideoTrack.preferredTransform = transform

                // Add audio track if present
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                if let audioTrack = audioTracks.first,
                   let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: .zero)
                }

                // Create caption layer
                let captionLayer = self.createCaptionLayer(captions: captions, videoSize: size, duration: duration)

                // Create video layer
                let videoLayer = CALayer()
                videoLayer.frame = CGRect(origin: .zero, size: size)

                // Create parent layer
                let parentLayer = CALayer()
                parentLayer.frame = CGRect(origin: .zero, size: size)
                parentLayer.addSublayer(videoLayer)
                parentLayer.addSublayer(captionLayer)

                // Create video composition
                let videoComposition = AVMutableVideoComposition()
                videoComposition.renderSize = size
                videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
                videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)

                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
                instruction.layerInstructions = [layerInstruction]
                videoComposition.instructions = [instruction]

                // Export
                let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("captioned_\(UUID().uuidString).mov")

                guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                    completion(nil, NSError(domain: "CaptionRenderer", code: -3, userInfo: [NSLocalizedDescriptionKey: "Could not create export session"]))
                    return
                }

                exportSession.outputURL = outputURL
                exportSession.outputFileType = .mov
                exportSession.videoComposition = videoComposition

                await exportSession.export()

                DispatchQueue.main.async {
                    if exportSession.status == .completed {
                        print("Caption rendering complete: \(outputURL)")
                        completion(outputURL, nil)
                    } else {
                        completion(nil, exportSession.error)
                    }
                }

            } catch {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
            }
        }
    }

    private func createCaptionLayer(captions: [CaptionSegment], videoSize: CGSize, duration: CMTime) -> CALayer {
        let containerLayer = CALayer()
        containerLayer.frame = CGRect(origin: .zero, size: videoSize)

        for caption in captions {
            let textLayer = CATextLayer()
            textLayer.string = createAttributedString(text: caption.text, videoSize: videoSize)
            textLayer.alignmentMode = .center
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.isWrapped = true

            // Position at bottom center
            let textHeight: CGFloat = 80
            let margin: CGFloat = videoSize.height * 0.1
            textLayer.frame = CGRect(
                x: 20,
                y: margin,
                width: videoSize.width - 40,
                height: textHeight
            )

            // Animate opacity to show/hide caption
            let showAnimation = CAKeyframeAnimation(keyPath: "opacity")
            let durationSeconds = CMTimeGetSeconds(duration)
            let startRatio = caption.startTime / durationSeconds
            let endRatio = caption.endTime / durationSeconds

            showAnimation.keyTimes = [0, NSNumber(value: startRatio - 0.001), NSNumber(value: startRatio), NSNumber(value: endRatio), NSNumber(value: endRatio + 0.001), 1]
            showAnimation.values = [0, 0, 1, 1, 0, 0]
            showAnimation.duration = durationSeconds
            showAnimation.isRemovedOnCompletion = false
            showAnimation.beginTime = AVCoreAnimationBeginTimeAtZero

            textLayer.add(showAnimation, forKey: "opacity")
            textLayer.opacity = 0

            containerLayer.addSublayer(textLayer)
        }

        return containerLayer
    }

    private func createAttributedString(text: String, videoSize: CGSize) -> NSAttributedString {
        let fontSize: CGFloat = min(videoSize.width, videoSize.height) * 0.05

        // Use system font which supports both Latin and Devanagari
        let font = UIFont.boldSystemFont(ofSize: fontSize)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .strokeColor: UIColor.black,
            .strokeWidth: -3.0
        ]

        return NSAttributedString(string: text, attributes: attributes)
    }
}
