//
//  VideoProcessor.swift
//  CinematiCam
//
//  Created by Abhishek Dangol on 1/29/26.
//

import AVFoundation

class VideoProcessor {

    /// Trims a video based on start/end percentages (0.0 to 1.0)
    func trimVideo(
        sourceURL: URL,
        trimStart: Double,
        trimEnd: Double,
        completion: @escaping (URL?, Error?) -> Void
    ) {
        let asset = AVAsset(url: sourceURL)

        Task {
            do {
                let duration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(duration)

                // Convert percentages to times
                let startTime = CMTime(seconds: durationSeconds * trimStart, preferredTimescale: 600)
                let endTime = CMTime(seconds: durationSeconds * trimEnd, preferredTimescale: 600)
                let trimDuration = CMTimeSubtract(endTime, startTime)

                // If no trimming needed (full video), just return the original
                if trimStart == 0.0 && trimEnd == 1.0 {
                    DispatchQueue.main.async {
                        completion(sourceURL, nil)
                    }
                    return
                }

                // Create composition
                let composition = AVMutableComposition()

                // Add video track
                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
                      let compositionVideoTrack = composition.addMutableTrack(
                        withMediaType: .video,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                      ) else {
                    throw VideoProcessorError.noVideoTrack
                }

                let timeRange = CMTimeRange(start: startTime, duration: trimDuration)
                try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)

                // Copy video transform
                let transform = try await videoTrack.load(.preferredTransform)
                compositionVideoTrack.preferredTransform = transform

                // Add audio track if present
                if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
                   let compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                   ) {
                    try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
                }

                // Export
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")

                guard let exportSession = AVAssetExportSession(
                    asset: composition,
                    presetName: AVAssetExportPresetHighestQuality
                ) else {
                    throw VideoProcessorError.exportSessionFailed
                }

                exportSession.outputURL = outputURL
                exportSession.outputFileType = .mov

                await exportSession.export()

                if exportSession.status == .completed {
                    DispatchQueue.main.async {
                        completion(outputURL, nil)
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(nil, exportSession.error ?? VideoProcessorError.exportFailed)
                    }
                }

            } catch {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
            }
        }
    }
}

enum VideoProcessorError: Error {
    case noVideoTrack
    case exportSessionFailed
    case exportFailed
}
