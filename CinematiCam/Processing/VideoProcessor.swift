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

    /// Exports video with multiple segments support (TikTok-style split)
    func exportWithSegments(
        sourceURL: URL,
        splitPoints: [Double],
        deletedSegments: Set<Int>,
        trimStart: Double,
        trimEnd: Double,
        volume: Double,
        completion: @escaping (URL?, Error?) -> Void
    ) {
        let asset = AVAsset(url: sourceURL)

        Task {
            do {
                let duration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(duration)

                // Calculate segments from split points
                var segments: [(start: Double, end: Double)] = []
                var lastPoint = trimStart

                let validSplits = splitPoints.filter { $0 > trimStart && $0 < trimEnd }.sorted()

                for split in validSplits {
                    segments.append((lastPoint, split))
                    lastPoint = split
                }
                segments.append((lastPoint, trimEnd))

                // Filter out deleted segments
                var keptSegments: [(start: Double, end: Double)] = []
                for (index, segment) in segments.enumerated() {
                    if !deletedSegments.contains(index) {
                        keptSegments.append(segment)
                    }
                }

                // If no segments left, return error
                if keptSegments.isEmpty {
                    DispatchQueue.main.async {
                        completion(nil, VideoProcessorError.noSegments)
                    }
                    return
                }

                // If only one segment and no volume change, check if it's the full video
                if keptSegments.count == 1 && volume == 1.0 {
                    let seg = keptSegments[0]
                    if seg.start == 0.0 && seg.end == 1.0 {
                        DispatchQueue.main.async {
                            completion(sourceURL, nil)
                        }
                        return
                    }
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

                // Copy video transform
                let transform = try await videoTrack.load(.preferredTransform)
                compositionVideoTrack.preferredTransform = transform

                // Add audio track if present
                let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
                var compositionAudioTrack: AVMutableCompositionTrack?
                if let audioTrack = audioTrack {
                    compositionAudioTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                }

                // Insert each kept segment
                var insertTime = CMTime.zero
                for segment in keptSegments {
                    let startTime = CMTime(seconds: durationSeconds * segment.start, preferredTimescale: 600)
                    let endTime = CMTime(seconds: durationSeconds * segment.end, preferredTimescale: 600)
                    let segmentDuration = CMTimeSubtract(endTime, startTime)
                    let timeRange = CMTimeRange(start: startTime, duration: segmentDuration)

                    try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: insertTime)

                    if let audioTrack = audioTrack, let compositionAudioTrack = compositionAudioTrack {
                        try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: insertTime)
                    }

                    insertTime = CMTimeAdd(insertTime, segmentDuration)
                }

                // Audio mix for volume control
                var audioMix: AVMutableAudioMix? = nil
                if volume != 1.0, let compositionAudioTrack = compositionAudioTrack {
                    let mix = AVMutableAudioMix()
                    let audioParams = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
                    audioParams.setVolume(Float(volume), at: .zero)
                    mix.inputParameters = [audioParams]
                    audioMix = mix
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
                if let audioMix = audioMix {
                    exportSession.audioMix = audioMix
                }

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

    /// Legacy: Exports video with optional single split (for backwards compatibility)
    func exportWithSplit(
        sourceURL: URL,
        trimStart: Double,
        trimEnd: Double,
        splitPosition: Double?,
        deletedSegment: Int?,
        volume: Double,
        completion: @escaping (URL?, Error?) -> Void
    ) {
        // Convert old format to new format
        var splitPoints: [Double] = []
        var deletedSegments: Set<Int> = []

        if let split = splitPosition {
            splitPoints = [split]
            if let deleted = deletedSegment {
                deletedSegments = [deleted]
            }
        }

        exportWithSegments(
            sourceURL: sourceURL,
            splitPoints: splitPoints,
            deletedSegments: deletedSegments,
            trimStart: trimStart,
            trimEnd: trimEnd,
            volume: volume,
            completion: completion
        )
    }
}

enum VideoProcessorError: Error {
    case noVideoTrack
    case exportSessionFailed
    case exportFailed
    case noSegments
}
