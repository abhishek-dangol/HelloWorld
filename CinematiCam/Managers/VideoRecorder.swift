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
    private var sessionStarted = false
    private let sessionLock = NSLock()
    private var outputURL: URL?

    init() {
        print("Recorder initialized")
    }

    private func configureWriter() {
        outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        guard let outputURL = outputURL else { return }

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

                // Set up pixel buffer adaptor for writing processed frames
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

            // Audio settings: AAC, 44.1kHz, stereo
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

            print("Writer configured")
        } catch {
            print("Error configuring writer: \(error.localizedDescription)")
        }
    }

    func startRecording() {
        configureWriter()
        guard let assetWriter = assetWriter else { return }

        assetWriter.startWriting()
        isRecording = true
        sessionStarted = false
        print("Recording started")
    }

    func writeVideoBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let assetWriter = assetWriter,
              let videoInput = videoInput,
              assetWriter.status == .writing else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        sessionLock.lock()
        if !sessionStarted {
            assetWriter.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }
        sessionLock.unlock()

        if videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
        }
    }

    func writePixelBuffer(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard isRecording,
              let assetWriter = assetWriter,
              let pixelBufferAdaptor = pixelBufferAdaptor,
              assetWriter.status == .writing else { return }

        sessionLock.lock()
        if !sessionStarted {
            assetWriter.startSession(atSourceTime: time)
            sessionStarted = true
        }
        sessionLock.unlock()

        if pixelBufferAdaptor.assetWriterInput.isReadyForMoreMediaData {
            pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: time)
        }
    }

    func writeAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        sessionLock.lock()
        let isSessionStarted = sessionStarted
        sessionLock.unlock()

        guard isRecording,
              isSessionStarted,
              let assetWriter = assetWriter,
              let audioInput = audioInput,
              assetWriter.status == .writing else { return }

        if audioInput.isReadyForMoreMediaData {
            audioInput.append(sampleBuffer)
        }
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording, let assetWriter = assetWriter else {
            completion(nil)
            return
        }

        isRecording = false

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        assetWriter.finishWriting { [weak self] in
            print("Recording stopped")
            if assetWriter.status == .completed {
                print("Video saved to: \(self?.outputURL?.path ?? "unknown")")
                completion(self?.outputURL)
            } else {
                print("Error finishing: \(assetWriter.error?.localizedDescription ?? "unknown")")
                completion(nil)
            }
        }
    }
}
