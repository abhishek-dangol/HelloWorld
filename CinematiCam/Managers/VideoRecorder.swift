import AVFoundation
import VideoToolbox

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
    /// Frames a second the camera delivers (30 or 60)
    var frameRate = 30
    /// Slo-mo: each frame is written this many times later than it was shot (4 = a quarter
    /// of the speed). Sound can't be stretched the same way, so such clips are silent.
    var slowFactor = 1
    /// Write 10-bit HEVC tagged BT.2020 / HLG (frames must be 10-bit YUV)
    var isHDR = false
    /// How the phone was held when the recording started (0 upright, 90 / -90 sideways,
    /// 180 upside down). The picture is stored as shot and tagged with this turn, so
    /// Photos and every player show it the right way up, like the Camera app's videos.
    var turnDegrees: Double = 0

    private var isRecording = false
    private var isPaused = false
    private var sessionStarted = false
    /// True from the moment a clip's file is ready for data until Pause or End shuts it
    private var clipOpen = false
    /// One thread at a time may touch the clip being written (its writer, its inputs and the
    /// values around here). The picture, the sound and the Pause / End buttons each run on
    /// their own thread. Without this, sound could be added to a clip at the very instant
    /// it was being shut, which iOS answers by closing the app (the lost recording of
    /// 2026-11-16).
    private let writerLock = NSLock()
    /// How often a clip being recorded is made playable up to that point
    private static let safePointSeconds = 5.0
    private var currentSegmentURL: URL?

    // Multi-segment support
    private var segmentURLs: [URL] = []
    private var segmentDurations: [Double] = []
    private var currentSegmentStartTime: CMTime?
    private var currentSegmentDuration: Double = 0

    init() {
        print("Recorder initialized")
    }

    /// Call with writerLock held
    private func configureWriter() {
        // Nothing of the clip before may be left standing if this one cannot be set up
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil
        if let takeFolder = takeFolder {
            // Numbered in the order they were shot, so a take can be put back together
            // after a crash
            currentSegmentURL = takeFolder.appendingPathComponent(String(format: "clip-%04d.mov", clipNumber))
        } else {
            currentSegmentURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
        }
        clipNumber += 1

        guard let outputURL = currentSegmentURL else { return }

        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            // The file is made playable every few seconds while recording, so that if the app
            // is ever closed mid-recording the clip still opens up to that point. Without
            // this a clip that was never finished cannot be played at all.
            assetWriter?.movieFragmentInterval = CMTime(seconds: Self.safePointSeconds, preferredTimescale: 600)

            let videoSettings = makeVideoSettings()
            videoInput = WriterGuard.makeInput(.video, settings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            if turnDegrees != 0 {
                // Icons turn WITH the phone; the picture has to be turned back the other way
                videoInput?.transform = CGAffineTransform(rotationAngle: -turnDegrees * .pi / 180)
            }

            if let videoInput = videoInput, assetWriter?.canAdd(videoInput) == true {
                assetWriter?.add(videoInput)

                let attributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: isHDR ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_32BGRA,
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

            audioInput = nil
            if slowFactor == 1 {
                audioInput = WriterGuard.makeInput(.audio, settings: audioSettings)
                audioInput?.expectsMediaDataInRealTime = true

                if let audioInput = audioInput, assetWriter?.canAdd(audioInput) == true {
                    assetWriter?.add(audioInput)
                }
            }

            print("Writer configured for segment \(segmentURLs.count + 1)")
        } catch {
            print("Error configuring writer: \(error.localizedDescription)")
        }
    }

    /// Apple's recommended encoder settings for the output size (HEVC for 1080p/4K,
    /// Apple's H.264 preset for 720p), with dimensions swapped to portrait.
    private func makeVideoSettings() -> [String: Any] {
        let preset: AVOutputSettingsPreset
        switch quality {
        case "4K": preset = .hevc3840x2160
        case "720p": preset = .preset1280x720
        default: preset = .hevc1920x1080
        }

        guard var settings = AVOutputSettingsAssistant(preset: preset)?.videoSettings else {
            // Fallback if the assistant is unavailable: HEVC with encoder-chosen bitrate
            return [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: videoSize.width,
                AVVideoHeightKey: videoSize.height
            ]
        }
        settings[AVVideoWidthKey] = videoSize.width
        settings[AVVideoHeightKey] = videoSize.height

        if isHDR {
            // 10-bit HEVC tagged BT.2020 / HLG, which Photos shows as HDR. Keep only the
            // preset's bitrate: its other keys can be H.264-only (720p preset).
            let presetCompression = settings[AVVideoCompressionPropertiesKey] as? [String: Any]
            var compression: [String: Any] = [AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String]
            if let bitrate = presetCompression?[AVVideoAverageBitRateKey] {
                compression[AVVideoAverageBitRateKey] = bitrate
            }
            settings[AVVideoCodecKey] = AVVideoCodecType.hevc
            settings[AVVideoCompressionPropertiesKey] = compression
            settings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
            ]
        }

        // Twice the frames need more data to stay as sharp: half again, about the step the
        // iPhone Camera's own files take from 30 to 60
        if frameRate > 30, var faster = settings[AVVideoCompressionPropertiesKey] as? [String: Any] {
            if let bitrate = faster[AVVideoAverageBitRateKey] as? NSNumber {
                faster[AVVideoAverageBitRateKey] = Int(bitrate.doubleValue * 1.5)
            }
            faster[AVVideoExpectedSourceFrameRateKey] = frameRate
            settings[AVVideoCompressionPropertiesKey] = faster
        }

        let compression = settings[AVVideoCompressionPropertiesKey] as? [String: Any]
        print("Encoder: \(settings[AVVideoCodecKey] ?? "?") \(Int(videoSize.width))x\(Int(videoSize.height)), bitrate=\(compression?[AVVideoAverageBitRateKey] ?? "auto"), HDR=\(isHDR)")
        return settings
    }

    // MARK: - Multi-segment Recording

    func startRecording() {
        if usesDelayedStream {
            delayedStart()
            return
        }
        // Clear previous segments
        segmentURLs.removeAll()
        segmentDurations.removeAll()
        isPaused = false
        beginTake()
        startNewSegment()
    }

    private func startNewSegment() {
        writerLock.lock()
        configureWriter()
        // A new clip takes nothing until its first frame opens it. These are set before the
        // lock is let go, so the sound thread can never see the new clip together with the
        // old clip's "already started".
        sessionStarted = false
        currentSegmentStartTime = nil
        currentSegmentDuration = 0
        let hasWriter = assetWriter != nil
        clipOpen = assetWriter.map { WriterGuard.startWriting($0) } ?? false
        if hasWriter, !clipOpen {
            print("Segment could not be started: \(String(describing: assetWriter?.error))")
        }
        writerLock.unlock()
        guard hasWriter else { return }

        isRecording = true
        isPaused = false
        print("Recording segment started")
    }

    /// Shuts the clip being written, so that nothing more can be added to it, and hands back
    /// what is needed to finish its file. Nil when no clip is open (already shut, or it could
    /// not be started).
    private func closeClip() -> (writer: AVAssetWriter, url: URL?, duration: Double)? {
        writerLock.lock()
        defer { writerLock.unlock() }
        guard clipOpen, let writer = assetWriter else { return nil }
        clipOpen = false
        if let videoInput = videoInput { WriterGuard.finishInput(videoInput) }
        if let audioInput = audioInput { WriterGuard.finishInput(audioInput) }
        return (writer, currentSegmentURL, currentSegmentDuration)
    }

    func pauseRecording() {
        if usesDelayedStream {
            delayedPause()
            return
        }
        guard isRecording, !isPaused else { return }

        isPaused = true
        isRecording = false

        // Finish current segment. Shutting it hands back this clip's own writer, file and
        // length: Resume may start the next clip before this one has finished being written
        guard let clip = closeClip() else { return }
        let assetWriter = clip.writer
        let url = clip.url
        let duration = clip.duration

        // The clip takes its place in the take straight away, so clips stay in the order they
        // were shot. End waits (finishGroup) until every clip is fully written.
        if let url = url {
            segmentURLs.append(url)
            segmentDurations.append(duration)
        }
        finishGroup.enter()
        WriterGuard.finishWriting(assetWriter) { [weak self] in
            let written = assetWriter.status == .completed
            if written {
                print("Segment saved: \(duration)s")
            } else {
                print("Segment failed: status=\(assetWriter.status.rawValue) error=\(String(describing: assetWriter.error))")
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                // A clip that could not be written gives its place back
                if !written, let url = url, let index = self.segmentURLs.firstIndex(of: url) {
                    self.segmentURLs.remove(at: index)
                    self.segmentDurations.remove(at: index)
                }
                self.finishGroup.leave()
            }
        }
    }

    func resumeRecording() {
        if usesDelayedStream {
            delayedResume()
            return
        }
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
        }
        writerLock.lock()
        if clipOpen, let assetWriter = assetWriter {
            clipOpen = false
            WriterGuard.cancel(assetWriter)
        }
        let currentURL = currentSegmentURL
        currentSegmentURL = nil
        writerLock.unlock()

        // Delete all segment files
        for url in segmentURLs {
            try? FileManager.default.removeItem(at: url)
        }
        if let currentURL = currentURL {
            try? FileManager.default.removeItem(at: currentURL)
        }

        segmentURLs.removeAll()
        segmentDurations.removeAll()
        if let folder = releaseTake() {
            try? FileManager.default.removeItem(at: folder)
        }

        delayedLock.lock()
        finishAt = nil
        resumeAt = nil
        afterSegmentFinished = nil
        pendingAudio.removeAll()
        delayedLock.unlock()
        print("All segments discarded")
    }

    // MARK: - Writing Buffers

    func writePixelBuffer(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        if usesDelayedStream {
            delayedWrite(pixelBuffer, at: time)
            return
        }
        guard isRecording, !isPaused else { return }
        appendVideoFrame(pixelBuffer, at: time)
    }

    private func appendVideoFrame(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        // Held to the end: Pause and End wait for this frame and then shut the clip, so a
        // frame can never land in a clip that is already shut
        writerLock.lock()
        defer { writerLock.unlock() }
        guard clipOpen,
              let assetWriter = assetWriter,
              let pixelBufferAdaptor = pixelBufferAdaptor,
              assetWriter.status == .writing else { return }

        if !sessionStarted {
            guard WriterGuard.startSession(assetWriter, at: time) else { return }
            sessionStarted = true
            currentSegmentStartTime = time
        }

        // Slo-mo: the gap since the clip's first frame, stretched
        var stamp = time
        if slowFactor > 1, let start = currentSegmentStartTime {
            let gap = CMTimeSubtract(time, start)
            stamp = CMTimeAdd(start, CMTimeMultiply(gap, multiplier: Int32(slowFactor)))
        }

        // Update duration
        if let startTime = currentSegmentStartTime {
            currentSegmentDuration = CMTimeGetSeconds(stamp) - CMTimeGetSeconds(startTime)
        }

        if pixelBufferAdaptor.assetWriterInput.isReadyForMoreMediaData {
            _ = WriterGuard.appendPixels(pixelBuffer, at: stamp, to: pixelBufferAdaptor)
        }
    }

    func writeAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        if usesDelayedStream {
            // Hold audio until the delayed video catches up (see flushAudio)
            delayedLock.lock()
            if isRecording {
                pendingAudio.append(sampleBuffer)
            }
            delayedLock.unlock()
            return
        }
        guard isRecording, !isPaused else { return }
        appendAudio(sampleBuffer)
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        // The same lock as the picture and the Pause / End buttons: sound is only added
        // while the clip is open and its first frame has started it
        writerLock.lock()
        defer { writerLock.unlock() }
        guard clipOpen, sessionStarted,
              let assetWriter = assetWriter,
              let audioInput = audioInput,
              assetWriter.status == .writing else { return }

        if audioInput.isReadyForMoreMediaData {
            _ = WriterGuard.appendSample(sampleBuffer, to: audioInput)
        }
    }

    // MARK: - Finish Recording

    func stopRecording(completion: @escaping (URL?) -> Void) {
        if usesDelayedStream {
            delayedStop(completion: completion)
            return
        }
        // If currently recording, finish the current segment first
        if isRecording {
            isRecording = false

            guard let clip = closeClip() else {
                // No clip was open (it could not be started): join what was shot before it
                finishGroup.notify(queue: .global(qos: .userInitiated)) { [weak self] in
                    guard let self = self else {
                        completion(nil)
                        return
                    }
                    self.mergeSegments(completion: completion)
                }
                return
            }

            let assetWriter = clip.writer
            let url = clip.url
            let duration = clip.duration
            WriterGuard.finishWriting(assetWriter) { [weak self] in
                guard let self = self else {
                    completion(nil)
                    return
                }

                if assetWriter.status == .completed, let url = url {
                    self.segmentURLs.append(url)
                    self.segmentDurations.append(duration)
                } else {
                    print("Final segment failed: status=\(assetWriter.status.rawValue) error=\(String(describing: assetWriter.error))")
                }

                // A clip paused a moment ago may still be finishing: join once all are written
                self.finishGroup.notify(queue: .global(qos: .userInitiated)) {
                    self.mergeSegments(completion: completion)
                }
            }
        } else {
            // Already paused: join once the paused clip is fully written
            finishGroup.notify(queue: .main) { [weak self] in
                guard let self = self else {
                    completion(nil)
                    return
                }
                self.mergeSegments(completion: completion)
            }
        }
    }

    // MARK: - Delayed stream (Enhanced Stabilization)
    //
    // With heavy stabilization the recording stream runs behind real time. Start, pause,
    // and stop then become timestamps instead of immediate actions: frames captured
    // before a start are skipped, a pause/stop keeps writing until frames from the
    // moment it was pressed arrive, and audio is held back so it's written in step
    // with the delayed video.

    /// Set by CameraManager before a recording starts; don't change mid-recording
    var usesDelayedStream = false
    /// The capture session's clock, so "now" is comparable to frame timestamps
    var captureClock: CMClock = CMClockGetHostTimeClock()
    /// True while the recording stream's frames are still needed
    var wantsFrames: Bool { isRecording }

    private let delayedLock = NSLock()
    private var acceptFramesFrom: CMTime?
    private var finishAt: CMTime?
    private var resumeAt: CMTime?
    private var afterSegmentFinished: (() -> Void)?
    private var pendingAudio: [CMSampleBuffer] = []
    private let finishGroup = DispatchGroup()
    /// If frames stop arriving (e.g., app backgrounded), finish the segment anyway
    private let finishTimeout: TimeInterval = 3

    private var now: CMTime { CMClockGetTime(captureClock) }

    private func delayedStart() {
        delayedLock.lock()
        segmentURLs.removeAll()
        segmentDurations.removeAll()
        pendingAudio.removeAll()
        finishAt = nil
        resumeAt = nil
        afterSegmentFinished = nil
        acceptFramesFrom = now
        delayedLock.unlock()
        beginTake()
        startNewSegment()
    }

    private func delayedPause() {
        delayedLock.lock()
        // A pause right after a not-yet-started resume just cancels that resume
        resumeAt = nil
        guard isRecording, finishAt == nil else {
            delayedLock.unlock()
            return
        }
        let target = now
        finishAt = target
        delayedLock.unlock()
        scheduleFinishTimeout(for: target)
    }

    private func delayedResume() {
        delayedLock.lock()
        let target = now
        if finishAt != nil {
            // The previous segment is still waiting for its last frames; resume after it
            resumeAt = target
            delayedLock.unlock()
            return
        }
        guard !isRecording else {
            delayedLock.unlock()
            return
        }
        acceptFramesFrom = target
        delayedLock.unlock()
        startNewSegment()
    }

    private func delayedStop(completion: @escaping (URL?) -> Void) {
        let mergeWhenWritten = { [weak self] in
            guard let self = self else { return }
            self.finishGroup.notify(queue: .global(qos: .userInitiated)) {
                self.mergeSegments(completion: completion)
            }
        }

        delayedLock.lock()
        resumeAt = nil
        guard isRecording else {
            delayedLock.unlock()
            mergeWhenWritten()
            return
        }
        // Merge once this segment has started finishing (it joins finishGroup then)
        afterSegmentFinished = mergeWhenWritten
        var newTarget: CMTime?
        if finishAt == nil {
            newTarget = now
            finishAt = newTarget
        }
        delayedLock.unlock()
        if let newTarget = newTarget {
            scheduleFinishTimeout(for: newTarget)
        }
    }

    private func delayedWrite(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        delayedLock.lock()
        guard isRecording else {
            delayedLock.unlock()
            return
        }
        if let from = acceptFramesFrom, time < from {
            // Captured before the start/resume button was pressed
            delayedLock.unlock()
            return
        }
        if let target = finishAt, time >= target {
            // First frame after the pause/stop moment: this segment is complete
            delayedLock.unlock()
            finishDelayedSegment()
            // If a resume was queued, this frame may already belong to the new segment
            delayedWrite(pixelBuffer, at: time)
            return
        }
        delayedLock.unlock()

        appendVideoFrame(pixelBuffer, at: time)
        flushAudio(upTo: time)
    }

    /// Writes held audio up to the latest video frame, keeping the two tracks in step
    private func flushAudio(upTo time: CMTime) {
        delayedLock.lock()
        let ready = Array(pendingAudio.prefix { CMSampleBufferGetPresentationTimeStamp($0) <= time })
        pendingAudio.removeFirst(ready.count)
        delayedLock.unlock()
        ready.forEach(appendAudio)
    }

    private func finishDelayedSegment() {
        delayedLock.lock()
        guard isRecording, let target = finishAt else {
            delayedLock.unlock()
            return
        }
        let resume = resumeAt
        let afterFinished = afterSegmentFinished
        finishAt = nil
        resumeAt = nil
        afterSegmentFinished = nil
        isRecording = false

        // Audio before the pause belongs to this segment; keep later audio only if it
        // falls inside a queued resume
        let segmentAudio = Array(pendingAudio.prefix { CMSampleBufferGetPresentationTimeStamp($0) < target })
        pendingAudio.removeFirst(segmentAudio.count)
        if let resume = resume {
            pendingAudio.removeAll { CMSampleBufferGetPresentationTimeStamp($0) < resume }
        } else {
            pendingAudio.removeAll()
        }
        delayedLock.unlock()

        segmentAudio.forEach(appendAudio)
        if let clip = closeClip() {
            let writer = clip.writer
            let segmentURL = clip.url
            let duration = clip.duration
            finishGroup.enter()
            WriterGuard.finishWriting(writer) { [weak self] in
                if writer.status == .completed, let url = segmentURL {
                    self?.segmentURLs.append(url)
                    self?.segmentDurations.append(duration)
                    print("Segment \(self?.segmentURLs.count ?? 0) saved: \(duration)s (delayed stream)")
                } else {
                    print("Segment failed: status=\(writer.status.rawValue) error=\(String(describing: writer.error))")
                }
                self?.finishGroup.leave()
            }
        }

        if let resume = resume {
            delayedLock.lock()
            acceptFramesFrom = resume
            delayedLock.unlock()
            startNewSegment()
        } else {
            isPaused = true
        }
        afterFinished?()
    }

    private func scheduleFinishTimeout(for target: CMTime) {
        DispatchQueue.global().asyncAfter(deadline: .now() + finishTimeout) { [weak self] in
            guard let self = self else { return }
            self.delayedLock.lock()
            let stillPending = self.finishAt == target
            self.delayedLock.unlock()
            if stillPending {
                print("Recording frames stopped arriving; finishing segment after timeout")
                self.finishDelayedSegment()
            }
        }
    }

    private func mergeSegments(completion: @escaping (URL?) -> Void) {
        let clips = segmentURLs
        // The take is over for the recorder: from here its files belong to whoever saves it
        let folder = releaseTake()
        guard !clips.isEmpty else {
            if let folder = folder { try? FileManager.default.removeItem(at: folder) }
            completion(nil)
            return
        }

        // If only one segment, return it directly
        if clips.count == 1 {
            print("Single segment, no merge needed")
            segmentURLs.removeAll()
            segmentDurations.removeAll()
            completion(clips[0])
            return
        }

        let outputURL = folder?.appendingPathComponent(Self.joinedName)
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")

        Self.joinClips(clips, into: outputURL) { [weak self] joined in
            // The clips go only once the joined video exists. If the join failed they stay,
            // and the take is offered again the next time the app opens.
            if joined {
                for url in clips {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            self?.segmentURLs.removeAll()
            self?.segmentDurations.removeAll()
            completion(joined ? outputURL : nil)
        }
    }

    /// Joins clips, in the order given, into one video at `outputURL` without re-compressing them
    private static func joinClips(_ clips: [URL], into outputURL: URL, completion: @escaping (Bool) -> Void) {
        let composition = AVMutableComposition()

        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(false)
            return
        }

        var currentTime = CMTime.zero

        for segmentURL in clips {
            let asset = AVAsset(url: segmentURL)
            guard let assetVideoTrack = asset.tracks(withMediaType: .video).first else { continue }
            // Each clip is exactly as long as its picture. A clip's sound runs a few
            // hundredths of a second past its last frame; using the whole file's length
            // left that long a hole in the picture at every join, seen as a black flash.
            let videoRange = assetVideoTrack.timeRange

            do {
                // Keep the clips' own "which way is up" tag on the joined video
                if currentTime == .zero {
                    videoTrack.preferredTransform = assetVideoTrack.preferredTransform
                }
                try videoTrack.insertTimeRange(videoRange, of: assetVideoTrack, at: currentTime)

                if let assetAudioTrack = asset.tracks(withMediaType: .audio).first {
                    // Only the sound that falls inside the picture, kept at its own offset
                    let audioRange = assetAudioTrack.timeRange.intersection(videoRange)
                    if audioRange.duration > .zero {
                        let offset = CMTimeSubtract(audioRange.start, videoRange.start)
                        try audioTrack.insertTimeRange(audioRange,
                                                        of: assetAudioTrack,
                                                        at: CMTimeAdd(currentTime, offset))
                    }
                }

                currentTime = CMTimeAdd(currentTime, videoRange.duration)
            } catch {
                print("Error merging segment: \(error)")
            }
        }

        // Segments without audio leave an empty track, which passthrough export can't write
        if audioTrack.segments.isEmpty {
            composition.removeTrack(audioTrack)
        }

        // Passthrough joins the already-encoded segments without re-compressing them
        guard currentTime > .zero,
              let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            completion(false)
            return
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mov

        exporter.exportAsynchronously {
            if exporter.status == .completed {
                print("Joined \(clips.count) clips")
                completion(true)
            } else {
                print("Export failed: \(exporter.error?.localizedDescription ?? "unknown")")
                completion(false)
            }
        }
    }

    // MARK: - Takes on disk, and getting one back after the app closed on it

    /// A take the app closed on before it reached Photos
    struct InterruptedTake {
        let folder: URL
        /// Playable clips, in the order they were shot
        let clips: [URL]
        let seconds: Double
    }

    /// Where a take's clips live until the take is in Photos. Not the temporary folder: iOS
    /// may empty that whenever the app is not running, and a take has to outlive a crash.
    static let takesFolder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var folder = base.appendingPathComponent("Takes", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Large and short-lived: kept out of iCloud and computer backups
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        return folder
    }()
    private static let savedMark = "saved"
    private static let joinedName = "joined.mov"
    /// Takes begun in this run of the app: never "interrupted", whatever state they are in
    private static var liveTakes = Set<String>()
    private static let takesLock = NSLock()

    /// The folder of the take being shot (guarded by writerLock)
    private var takeFolder: URL?
    private var clipNumber = 0

    private func beginTake() {
        let folder = Self.takesFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let made = (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
        if made {
            Self.takesLock.lock()
            Self.liveTakes.insert(folder.lastPathComponent)
            Self.takesLock.unlock()
        }
        writerLock.lock()
        takeFolder = made ? folder : nil
        clipNumber = 0
        writerLock.unlock()
    }

    /// The recorder lets go of the take's folder and hands it back
    private func releaseTake() -> URL? {
        writerLock.lock()
        defer { writerLock.unlock() }
        let folder = takeFolder
        takeFolder = nil
        return folder
    }

    private static func isInTakesFolder(_ url: URL) -> Bool {
        url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == takesFolder.lastPathComponent
    }

    /// Call once a take's video is safely in Photos: its files are then cleared away the next
    /// time the app opens (they stay for now, the last-capture viewer plays from them).
    static func markSaved(_ url: URL) {
        guard isInTakesFolder(url) else { return }
        let mark = url.deletingLastPathComponent().appendingPathComponent(savedMark)
        FileManager.default.createFile(atPath: mark.path, contents: nil)
    }

    /// Throws away a video that was not saved, together with the rest of its take
    static func removeUnsaved(_ url: URL) {
        let target = isInTakesFolder(url) ? url.deletingLastPathComponent() : url
        try? FileManager.default.removeItem(at: target)
    }

    private static func playableSeconds(_ url: URL) -> Double {
        guard FileManager.default.fileExists(atPath: url.path),
              let track = AVURLAsset(url: url).tracks(withMediaType: .video).first else { return 0 }
        let seconds = CMTimeGetSeconds(track.timeRange.duration)
        return seconds.isFinite ? max(0, seconds) : 0
    }

    /// Takes left by an earlier run of the app that never reached Photos, oldest first. Takes
    /// that did reach Photos, and ones with nothing playable, are cleared away here.
    /// Opens every clip, so call it off the main thread.
    static func interruptedTakes() -> [InterruptedTake] {
        let files = FileManager.default
        takesLock.lock()
        let live = liveTakes
        takesLock.unlock()

        let folders = (try? files.contentsOfDirectory(at: takesFolder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        var found: [(made: Date, take: InterruptedTake)] = []
        for folder in folders where !live.contains(folder.lastPathComponent) {
            if files.fileExists(atPath: folder.appendingPathComponent(savedMark).path) {
                try? files.removeItem(at: folder)
                continue
            }
            // A take that was already joined is one finished video; otherwise its clips
            let joined = folder.appendingPathComponent(joinedName)
            var clips: [URL] = []
            var seconds = playableSeconds(joined)
            if seconds > 0 {
                clips = [joined]
            } else {
                let all = ((try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.lastPathComponent.hasPrefix("clip-") && $0.pathExtension == "mov" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                for clip in all {
                    let length = playableSeconds(clip)
                    if length > 0 {
                        clips.append(clip)
                        seconds += length
                    }
                }
            }
            if clips.isEmpty {
                try? files.removeItem(at: folder)
            } else {
                let made = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                found.append((made, InterruptedTake(folder: folder, clips: clips, seconds: seconds)))
            }
        }
        return found.sorted { $0.made < $1.made }.map { $0.take }
    }

    /// One finished video out of an interrupted take's clips (nil if it cannot be made)
    static func join(_ take: InterruptedTake, completion: @escaping (URL?) -> Void) {
        let joined = take.folder.appendingPathComponent(joinedName)
        if take.clips == [joined] {
            completion(joined)
            return
        }
        try? FileManager.default.removeItem(at: joined)
        joinClips(take.clips, into: joined) { done in
            completion(done ? joined : nil)
        }
    }

    static func remove(_ take: InterruptedTake) {
        try? FileManager.default.removeItem(at: take.folder)
    }
}
