import AudioToolbox
import AVFoundation
import Combine
import CoreImage
import Metal
import MetalPetal
import UIKit
import Vision

class CameraManager: NSObject, ObservableObject {

    let captureSession = AVCaptureSession()
    private var currentPosition: AVCaptureDevice.Position = .front
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    private let dataOutputQueue = DispatchQueue(label: "dataOutputQueue")
    private let audioQueue = DispatchQueue(label: "audioQueue")
    private var hasLoggedAudio = false

    @Published var depthImage: UIImage?
    @Published var filteredPreview: UIImage?
    var blurIntensity: Double = 0.5 // 0 = min blur (f/8), 1 = max blur (f/1.4)
    private let ciContext: CIContext
    private var mtiContext: MTIContext?
    private let mtiLock = NSLock()  // Thread safety for MTIContext
    private let depthMaskGenerator = DepthMaskGenerator()
    private let bokehRenderer = BokehRenderer()
    private let filterEngine = FilterEngine()
    private var frameCount = 0
    private var isProcessing = false
    private var isSwitchingCamera = false
    private let videoRecorder = VideoRecorder()
    private var hasLoggedFilter = false
    private var pixelBufferPool: CVPixelBufferPool?
    private var retouchPixelBufferPool: CVPixelBufferPool?
    private var currentVideoSize = CGSize(width: 1080, height: 1920)
    private var retouchEnabled = false

    // Face detection for targeted smoothing
    private var cachedFaceBounds: CGRect?
    private var faceDetectionCounter = 0
    private let faceDetectionInterval = 10  // Run detection every N frames
    private let faceDetectionQueue = DispatchQueue(label: "faceDetectionQueue", qos: .userInitiated)

    // Adjustable retouch parameters
    var retouchAmount: Float = 0.5         // Smoothing intensity (0.0 - 1.0)
    var retouchRadius: Float = 9.0         // Blur radius (1.0 - 15.0)
    var skinBrightness: Float = 0.0        // Skin glow effect (-0.1 - 0.2)
    var skinWarmth: Float = 0.0            // Warm/cool skin tone (-0.3 - 0.3)
    var edgeSoftness: Float = 0.3          // Mask feathering (0.1 - 0.5)
    var faceExpansion: Float = 0.15        // How much to expand face region (0.0 - 0.4)

    private func videoSize(for quality: String) -> CGSize {
        switch quality {
        case "4K": return CGSize(width: 2160, height: 3840)
        case "720p": return CGSize(width: 720, height: 1280)
        default: return CGSize(width: 1080, height: 1920)
        }
    }

    override init() {
        // Use Metal-accelerated context for better performance
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: metalDevice)
            // Initialize MetalPetal context for skin smoothing
            do {
                mtiContext = try MTIContext(device: metalDevice)
                print("MetalPetal context initialized")
            } catch {
                print("Failed to create MTIContext: \(error)")
                mtiContext = nil
            }
        } else {
            ciContext = CIContext()
            mtiContext = nil
        }
        super.init()
        setupPixelBufferPool(for: currentVideoSize)
    }

    private func setupPixelBufferPool(for size: CGSize) {
        currentVideoSize = size
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pixelBufferPool)
    }

    private func getCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back {
            if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                return dualWide
            }
            if let dual = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                return dual
            }
            if let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                return wide
            }
            return nil
        } else {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
    }

    func configure() {
        guard let camera = getCamera(for: .front) else { return }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            return
        }

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        configureDepthOutput()
        configureAudioInput()
    }

    private func configureAudioInput() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard granted, let self = self else {
                print("Mic permission denied")
                return
            }

            DispatchQueue.main.async {
                self.captureSession.beginConfiguration()

                guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
                    self.captureSession.commitConfiguration()
                    return
                }

                do {
                    let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                    if self.captureSession.canAddInput(audioInput) {
                        self.captureSession.addInput(audioInput)
                    }
                } catch {
                    print("Error adding audio input: \(error.localizedDescription)")
                    self.captureSession.commitConfiguration()
                    return
                }

                self.audioOutput.setSampleBufferDelegate(self, queue: self.audioQueue)
                if self.captureSession.canAddOutput(self.audioOutput) {
                    self.captureSession.addOutput(self.audioOutput)
                    print("Audio input added")
                }

                self.captureSession.commitConfiguration()
            }
        }
    }

    private func configureDepthOutput() {
        depthOutput.isFilteringEnabled = true
        if captureSession.canAddOutput(depthOutput) {
            captureSession.addOutput(depthOutput)
        }
    }

    private func configureSynchronizer() {
        guard let depthConnection = depthOutput.connection(with: .depthData),
              depthConnection.isEnabled else {
            outputSynchronizer = nil
            return
        }
        outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
        outputSynchronizer?.setDelegate(self, queue: dataOutputQueue)
    }

    func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    func switchCamera() {
        isSwitchingCamera = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let newPosition: AVCaptureDevice.Position = (self.currentPosition == .front) ? .back : .front
            guard let newCamera = self.getCamera(for: newPosition) else {
                self.isSwitchingCamera = false
                print("Failed to get camera for position: \(newPosition)")
                return
            }

            self.captureSession.beginConfiguration()

            // Remove only the video input, not audio
            for input in self.captureSession.inputs {
                if let deviceInput = input as? AVCaptureDeviceInput,
                   deviceInput.device.hasMediaType(.video) {
                    self.captureSession.removeInput(deviceInput)
                }
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: newCamera)
                if self.captureSession.canAddInput(newInput) {
                    self.captureSession.addInput(newInput)
                    self.currentPosition = newPosition
                    print("Switched to \(newPosition == .front ? "front" : "back") camera")
                }
            } catch {
                print("Failed to switch camera: \(error.localizedDescription)")
            }

            self.captureSession.commitConfiguration()
            self.configureSynchronizer()

            // Clear old preview and allow new frames on main thread
            DispatchQueue.main.async {
                self.filteredPreview = nil
                self.isSwitchingCamera = false
                self.retouchPixelBufferPool = nil  // Reset pool for new camera resolution
            }
        }
    }

    func toggleFlash() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else {
            return false
        }

        do {
            try device.lockForConfiguration()
            device.torchMode = (device.torchMode == .off) ? .on : .off
            device.unlockForConfiguration()
            return device.torchMode == .on
        } catch {
            return false
        }
    }

    func startRecording(quality: String = "1080p") {
        let size = videoSize(for: quality)
        setupPixelBufferPool(for: size)
        videoRecorder.quality = quality
        videoRecorder.startRecording()
    }

    func pauseRecording() {
        videoRecorder.pauseRecording()
    }

    func resumeRecording() {
        videoRecorder.resumeRecording()
    }

    func undoLastSegment() -> Bool {
        return videoRecorder.undoLastSegment()
    }

    func discardAllSegments() {
        videoRecorder.discardAllSegments()
    }

    func hasRecordedSegments() -> Bool {
        return videoRecorder.hasSegments()
    }

    func getSegmentCount() -> Int {
        return videoRecorder.getSegmentCount()
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        videoRecorder.stopRecording(completion: completion)
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        // Play shutter sound (system sound 1108 is the camera shutter)
        AudioServicesPlaySystemSound(1108)

        // Return the current filtered preview as a photo
        DispatchQueue.main.async { [weak self] in
            completion(self?.filteredPreview)
        }
    }

    func setFilter(_ filter: Filter) {
        filterEngine.selectedFilter = filter
        print("Filter applied: \(filter.name)")
    }

    func setFilterIntensity(_ intensity: Double) {
        filterEngine.intensity = intensity
    }

    func setRetouch(_ enabled: Bool) {
        retouchEnabled = enabled
        print("Retouch: \(enabled ? "ON" : "OFF")")
    }

    // MARK: - Retouch Parameter Setters

    /// Set smoothing intensity (0.0 = none, 1.0 = maximum)
    func setRetouchAmount(_ amount: Float) {
        retouchAmount = max(0, min(1, amount))
    }

    /// Set blur radius (1.0 = subtle, 15.0 = strong)
    func setRetouchRadius(_ radius: Float) {
        retouchRadius = max(1, min(15, radius))
    }

    /// Set skin brightness/glow (-0.1 = darker, 0.2 = brighter glow)
    func setSkinBrightness(_ brightness: Float) {
        skinBrightness = max(-0.1, min(0.2, brightness))
    }

    /// Set skin warmth (-0.3 = cooler/paler, 0.3 = warmer/golden)
    func setSkinWarmth(_ warmth: Float) {
        skinWarmth = max(-0.3, min(0.3, warmth))
    }

    /// Set edge softness (0.1 = sharp edge, 0.5 = very soft blend)
    func setEdgeSoftness(_ softness: Float) {
        edgeSoftness = max(0.1, min(0.5, softness))
    }

    /// Set face region expansion (0.0 = tight, 0.4 = includes neck/forehead)
    func setFaceExpansion(_ expansion: Float) {
        faceExpansion = max(0, min(0.4, expansion))
    }

    /// Reset all retouch parameters to defaults
    func resetRetouchParameters() {
        retouchAmount = 0.5
        retouchRadius = 9.0
        skinBrightness = 0.0
        skinWarmth = 0.0
        edgeSoftness = 0.3
        faceExpansion = 0.15
    }

    /// Apply a preset
    func applyRetouchPreset(_ preset: RetouchPreset) {
        switch preset {
        case .natural:
            retouchAmount = 0.5
            retouchRadius = 5.0
            skinBrightness = 0.0
            skinWarmth = 0.0
            edgeSoftness = 0.3
            faceExpansion = 0.15
        case .soft:
            retouchAmount = 0.75
            retouchRadius = 7.0
            skinBrightness = 0.05
            skinWarmth = 0.05
            edgeSoftness = 0.35
            faceExpansion = 0.2
        case .glam:
            retouchAmount = 0.9
            retouchRadius = 10.0
            skinBrightness = 0.1
            skinWarmth = 0.1
            edgeSoftness = 0.4
            faceExpansion = 0.25
        case .porcelain:
            retouchAmount = 1.0
            retouchRadius = 12.0
            skinBrightness = 0.15
            skinWarmth = -0.1
            edgeSoftness = 0.45
            faceExpansion = 0.3
        }
    }

    private func applyRetouchToPixelBuffer(_ inputBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        // Run face detection periodically (not every frame)
        faceDetectionCounter += 1
        if faceDetectionCounter >= faceDetectionInterval {
            faceDetectionCounter = 0
            let ciImage = CIImage(cvPixelBuffer: inputBuffer)
            detectFace(in: ciImage)
        }

        // If no face detected, return nil (use original)
        guard cachedFaceBounds != nil else {
            return nil
        }

        // Use lock for thread-safe MTIContext access
        mtiLock.lock()
        defer { mtiLock.unlock() }

        guard let mtiContext = mtiContext else {
            return nil
        }

        // Create MTIImage directly from CVPixelBuffer (no CIImage conversion!)
        let mtiImage = MTIImage(cvPixelBuffer: inputBuffer, alphaType: .alphaIsOne)

        // Apply high-pass skin smoothing filter
        let smoothingFilter = MTIHighPassSkinSmoothingFilter()
        smoothingFilter.inputImage = mtiImage
        smoothingFilter.amount = retouchAmount
        smoothingFilter.radius = retouchRadius

        guard let smoothedMTI = smoothingFilter.outputImage else {
            return nil
        }

        // Render to pixel buffer
        do {
            let width = Int(smoothedMTI.size.width)
            let height = Int(smoothedMTI.size.height)

            // Create/reuse pixel buffer pool for retouch output
            if retouchPixelBufferPool == nil {
                let poolAttrs: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ]
                CVPixelBufferPoolCreate(nil, nil, poolAttrs as CFDictionary, &retouchPixelBufferPool)
            }

            var outputPixelBuffer: CVPixelBuffer?
            if let pool = retouchPixelBufferPool {
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputPixelBuffer)
            }

            guard let outputBuffer = outputPixelBuffer else {
                return nil
            }

            // Render directly to pixel buffer
            try mtiContext.render(smoothedMTI, to: outputBuffer)

            return outputBuffer
        } catch {
            print("MetalPetal render error: \(error)")
            return nil
        }
    }

    private func detectFace(in image: CIImage) {
        // Run face detection on background queue to avoid blocking video pipeline
        faceDetectionQueue.async { [weak self] in
            let request = VNDetectFaceRectanglesRequest { request, error in
                guard error == nil,
                      let results = request.results as? [VNFaceObservation],
                      let face = results.first else {
                    // No face detected - clear cache
                    self?.cachedFaceBounds = nil
                    return
                }
                // Cache the face bounds (normalized coordinates)
                self?.cachedFaceBounds = face.boundingBox
            }

            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            try? handler.perform([request])
        }
    }

    private func createFaceMask(rect: CGRect, imageExtent: CGRect) -> CIImage {
        // Create a radial gradient mask centered on face for soft edges
        let centerX = rect.midX
        let centerY = rect.midY
        let radius = max(rect.width, rect.height) / 2

        // Edge softness controls the feathering (0.1 = hard edge, 0.5 = very soft)
        let innerRadius = radius * CGFloat(1.0 - edgeSoftness)
        let outerRadius = radius * CGFloat(1.0 + edgeSoftness)

        let gradientFilter = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: centerX, y: centerY),
            "inputRadius0": innerRadius,  // Inner radius (full effect)
            "inputRadius1": outerRadius,  // Outer radius (feathered edge)
            "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),  // White = show smoothed
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 1)   // Black = show original
        ])

        return gradientFilter?.outputImage?.cropped(to: imageExtent) ?? CIImage.white
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == videoOutput {
            processVideoFrame(sampleBuffer)
        } else if output == audioOutput {
            if !hasLoggedAudio {
                print("Audio samples received")
                hasLoggedAudio = true
            }
            videoRecorder.writeAudioBuffer(sampleBuffer)
        }
    }

    private func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard !isSwitchingCamera else { return }
        guard var pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Apply retouch (skin smoothing) directly to pixel buffer if enabled
        if retouchEnabled {
            if let smoothedBuffer = applyRetouchToPixelBuffer(pixelBuffer) {
                pixelBuffer = smoothedBuffer
            }
        }

        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        ciImage = ciImage.oriented(.right)

        // Mirror front camera horizontally for selfie mode (like native camera/TikTok)
        if currentPosition == .front {
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                .translatedBy(x: -ciImage.extent.width, y: 0))
        }

        // Apply skin brightness/warmth if retouch is enabled
        if retouchEnabled {
            let extent = ciImage.extent
            if skinBrightness != 0 {
                ciImage = ciImage.applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: skinBrightness
                ]).cropped(to: extent)
            }
            if skinWarmth != 0 {
                ciImage = ciImage.applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500 - CGFloat(skinWarmth * 2000), y: 0),
                    "inputTargetNeutral": CIVector(x: 6500, y: 0)
                ]).cropped(to: extent)
            }
        }

        // Apply filter
        let filteredImage = filterEngine.applyFilter(to: ciImage)

        if !hasLoggedFilter && filterEngine.selectedFilter != nil {
            print("Filter rendering: \(filterEngine.selectedFilter!.name)")
            hasLoggedFilter = true
        }

        // Scale to video size and write to recorder
        let scaleX = currentVideoSize.width / filteredImage.extent.width
        let scaleY = currentVideoSize.height / filteredImage.extent.height
        let scaledImage = filteredImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(origin: .zero, size: currentVideoSize))

        if let pool = pixelBufferPool {
            var outputPixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputPixelBuffer)

            if let outputBuffer = outputPixelBuffer {
                // Render with explicit bounds to avoid memory issues
                ciContext.render(scaledImage, to: outputBuffer, bounds: CGRect(origin: .zero, size: currentVideoSize), colorSpace: CGColorSpaceCreateDeviceRGB())
                videoRecorder.writePixelBuffer(outputBuffer, at: timestamp)
            }
        }

        // Convert to UIImage for display
        guard let cgImage = ciContext.createCGImage(filteredImage, from: filteredImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)

        DispatchQueue.main.async { [weak self] in
            self?.filteredPreview = uiImage
        }
    }
}

extension CameraManager: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        // Depth data available for bokeh (disabled for now)
    }
}

enum RetouchPreset {
    case natural    // Subtle, barely noticeable
    case soft       // Balanced, everyday use
    case glam       // Strong smoothing with glow
    case porcelain  // Maximum smoothing, pale/flawless look
}
