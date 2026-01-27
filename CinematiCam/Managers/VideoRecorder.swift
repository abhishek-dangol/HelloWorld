import AVFoundation

class VideoRecorder {

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var videoSize: CGSize {
        switch quality {
        case "4K": return CGSize(width: 2160, height: 3840)
        case "720p": return CGSize(width: 720, height: 1280)
        default: return CGSize(width: 1080, height: 1920) // 1080p
        }
    }
    var quality: String = "1080p"

    private var isRecording = false
    private var isPaused = false
    private var sessionStarted = false
    private let sessionLock = NSLock()
    private var currentSegmentURL: URL?

    // Multi-segment support
    private var segmentURLs: [URL] = []
    private var segmentDurations: [Double] = []
    private var currentSegmentStartTime: CMTime?
    private var currentSegmentDuration: Double = 0

    init() {
        print("Recorder initialized")
    }

    private func configureWriter() {
        currentSegmentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        guard let outputURL = currentSegmentURL else { return }

        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: videoSize.width,
                AVVideoHeightKey: videoSize.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_000_000,
                    AVVideoExpectedSourceFrameRateKey: 30,
                    AVVideoMaxKeyFrameIntervalKey: 30
                ]
            ]

            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true

            if let videoInput = videoInput, assetWriter?.canAdd(videoInput) == true {
                assetWriter?.add(videoInput)

                let attributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: videoSize.width,
                    kCVPixelBufferHeightKey as String: videoSize.height
                ]
                pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: videoInput,
                    sourcePixelBufferAttributes: attributes
                )
            }

            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128000
            ]

            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput?.expectsMediaDataInRealTime = true

            if let audioInput = audioInput, assetWriter?.canAdd(audioInput) == true {
                assetWriter?.add(audioInput)
            }

            print("Writer configured for segment \(segmentURLs.count + 1)")
        } catch {
            print("Error configuring writer: \(error.localizedDescription)")
        }
    }

    // MARK: - Multi-segment Recording

    func startRecording() {
        // Clear previous segments
        segmentURLs.removeAll()
        segmentDurations.removeAll()
        isPaused = false
        startNewSegment()
    }

    private func startNewSegment() {
        configureWriter()
        guard let assetWriter = assetWriter else { return }

        assetWriter.startWriting()
        isRecording = true
        isPaused = false
        sessionStarted = false
        currentSegmentStartTime = nil
        currentSegmentDuration = 0
        print("Recording segment started")
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }

        isPaused = true
        isRecording = false

        // Finish current segment
        guard let assetWriter = assetWriter else { return }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        assetWriter.finishWriting { [weak self] in
            guard let self = self else { return }
            if assetWriter.status == .completed, let url = self.currentSegmentURL {
                self.segmentURLs.append(url)
                self.segmentDurations.append(self.currentSegmentDuration)
                print("Segment \(self.segmentURLs.count) saved: \(self.currentSegmentDuration)s")
            }
        }
    }

    func resumeRecording() {
        guard isPaused else { return }
        startNewSegment()
    }

    func undoLastSegment() -> Bool {
        guard !segmentURLs.isEmpty else { return false }

        let removedURL = segmentURLs.removeLast()
        segmentDurations.removeLast()

        // Delete the file
        try? FileManager.default.removeItem(at: removedURL)
        print("Removed segment, \(segmentURLs.count) segments remaining")

        return true
    }

    func getSegmentCount() -> Int {
        return segmentURLs.count + (isRecording ? 1 : 0)
    }

    func getTotalDuration() -> Double {
        return segmentDurations.reduce(0, +) + currentSegmentDuration
    }

    func hasSegments() -> Bool {
        return !segmentURLs.isEmpty || isRecording
    }

    func discardAllSegments() {
        // Stop recording if active
        if isRecording {
            isRecording = false
            isPaused = false
            assetWriter?.cancelWriting()
        }

        // Delete all segment files
        for url in segmentURLs {
            try? FileManager.default.removeItem(at: url)
        }
        if let currentURL = currentSegmentURL {
            try? FileManager.default.removeItem(at: currentURL)
        }

        segmentURLs.removeAll()
        segmentDurations.removeAll()
        currentSegmentURL = nil
        print("All segments discarded")
    }

    // MARK: - Writing Buffers

    func writeVideoBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, !isPaused,
              let assetWriter = assetWriter,
              let videoInput = videoInput,
              assetWriter.status == .writing else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        sessionLock.lock()
        if !sessionStarted {
            assetWriter.startSession(atSourceTime: timestamp)
            sessionStarted = true
            currentSegmentStartTime = timestamp
        }
        sessionLock.unlock()

        // Update duration
        if let startTime = currentSegmentStartTime {
            currentSegmentDuration = CMTimeGetSeconds(timestamp) - CMTimeGetSeconds(startTime)
        }

        if videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
        }
    }

    func writePixelBuffer(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard isRecording, !isPaused,
              let assetWriter = assetWriter,
              let pixelBufferAdaptor = pixelBufferAdaptor,
              assetWriter.status == .writing else { return }

        sessionLock.lock()
        if !sessionStarted {
            assetWriter.startSession(atSourceTime: time)
            sessionStarted = true
            currentSegmentStartTime = time
        }
        sessionLock.unlock()

        // Update duration
        if let startTime = currentSegmentStartTime {
            currentSegmentDuration = CMTimeGetSeconds(time) - CMTimeGetSeconds(startTime)
        }

        if pixelBufferAdaptor.assetWriterInput.isReadyForMoreMediaData {
            pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: time)
        }
    }

    func writeAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        sessionLock.lock()
        let isSessionStarted = sessionStarted
        sessionLock.unlock()

        guard isRecording, !isPaused, isSessionStarted,
              let assetWriter = assetWriter,
              let audioInput = audioInput,
              assetWriter.status == .writing else { return }

        if audioInput.isReadyForMoreMediaData {
            audioInput.append(sampleBuffer)
        }
    }

    // MARK: - Finish Recording

    func stopRecording(completion: @escaping (URL?) -> Void) {
        // If currently recording, finish the current segment first
        if isRecording {
            isRecording = false

            guard let assetWriter = assetWriter else {
                mergeSegments(completion: completion)
                return
            }

            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            assetWriter.finishWriting { [weak self] in
                guard let self = self else {
                    completion(nil)
                    return
                }

                if assetWriter.status == .completed, let url = self.currentSegmentURL {
                    self.segmentURLs.append(url)
                    self.segmentDurations.append(self.currentSegmentDuration)
                }

                self.mergeSegments(completion: completion)
            }
        } else {
            // Already paused, just merge
            mergeSegments(completion: completion)
        }
    }

    private func mergeSegments(completion: @escaping (URL?) -> Void) {
        guard !segmentURLs.isEmpty else {
            completion(nil)
            return
        }

        // If only one segment, return it directly
        if segmentURLs.count == 1 {
            print("Single segment, no merge needed")
            completion(segmentURLs.first)
            segmentURLs.removeAll()
            segmentDurations.removeAll()
            return
        }

        // Merge multiple segments
        let composition = AVMutableComposition()

        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(nil)
            return
        }

        var currentTime = CMTime.zero

        for segmentURL in segmentURLs {
            let asset = AVAsset(url: segmentURL)
            let duration = asset.duration

            do {
                if let assetVideoTrack = asset.tracks(withMediaType: .video).first {
                    try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                                    of: assetVideoTrack,
                                                    at: currentTime)
                }

                if let assetAudioTrack = asset.tracks(withMediaType: .audio).first {
                    try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                                    of: assetAudioTrack,
                                                    at: currentTime)
                }

                currentTime = CMTimeAdd(currentTime, duration)
            } catch {
                print("Error merging segment: \(error)")
            }
        }

        // Export merged video
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(nil)
            return
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mov

        exporter.exportAsynchronously { [weak self] in
            // Clean up segment files
            for url in self?.segmentURLs ?? [] {
                try? FileManager.default.removeItem(at: url)
            }
            self?.segmentURLs.removeAll()
            self?.segmentDurations.removeAll()

            switch exporter.status {
            case .completed:
                print("Merged \(self?.segmentURLs.count ?? 0) segments successfully")
                completion(outputURL)
            default:
                print("Export failed: \(exporter.error?.localizedDescription ?? "unknown")")
                completion(nil)
            }
        }
    }
}
