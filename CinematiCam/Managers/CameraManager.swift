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
    private var hasLoggedStabilization = false

    @Published var depthImage: UIImage?
    @Published var filteredPreview: UIImage?
    var blurIntensity: Double = 0.5 // 0 = min blur (f/8), 1 = max blur (f/1.4)
    /// Cinematic f-stop range for the active camera; nil when Cinematic Video isn't active
    @Published var apertureRange: ClosedRange<Float>?
    /// Current Cinematic f-stop (lower = stronger background blur)
    @Published var simulatedAperture: Float = CameraManager.portraitAperture
    /// Background blur, in Photo and Video alike.
    /// Always on since 2026-11-15: the Portrait button only shows or hides the strength slider
    private let portraitOn = true
    /// The blur strength Portrait starts with until the user picks their own (the Camera
    /// app's Portrait default)
    static let portraitAperture: Float = 4.5
    /// Zoom as shown on screen, like the Camera app: 1.0 = main lens, 0.5 = ultra-wide.
    @Published var displayZoom: CGFloat = 1.0
    /// The zoom buttons to show, like the Camera app's ".5  1x  2" row.
    @Published var zoomPresets: [CGFloat] = [1, 2]
    /// True while the selfie camera is in use. It gets one closer/wider button instead of
    /// the numbered zoom row, like the Camera app.
    @Published private(set) var isFrontCamera = true
    /// True while the camera changes between Photo and Video; the picture is blurred then.
    @Published private(set) var isModeSwitching = false
    /// Extra zoom done by cropping the picture, for cameras whose lens zoom is locked
    /// (Cinematic blur locks it on some cameras). 1 = none.
    private var digitalZoom: CGFloat = 1
    /// True while the back camera is on its real ultra-wide or telephoto lens, where
    /// Apple's background blur is not available (it only runs on the main lens).
    @Published var isBlurOffForZoom = false
    /// Back camera only: the all-lens camera is in the session instead of the blur camera.
    private var usesAllLenses = false
    /// True between record/resume and pause/stop. The camera is not swapped mid-clip.
    private var isRecordingActive = false
    private let ciContext: CIContext
    private var mtiContext: MTIContext?
    private let mtiLock = NSLock()  // Thread safety for MTIContext
    private let depthMaskGenerator = DepthMaskGenerator()
    private let bokehRenderer = BokehRenderer()
    private let filterEngine = FilterEngine()
    private var frameCount = 0
    private var isProcessing = false
    private var isSwitchingCamera = false
    /// Camera changes waiting or running (main thread). They run one at a time, in the order
    /// they were asked for, on sessionSetupQueue; frames wait until the last one is done.
    private var cameraChangesRunning = 0
    /// For the screen: the shutter waits while the camera is being changed
    var isCameraChanging: Bool { isSwitchingCamera }
    private let videoRecorder = VideoRecorder()
    private var hasLoggedFilter = false
    private var pixelBufferPool: CVPixelBufferPool?

    /// Per-stream buffer pools: the preview and recording streams can differ in size
    private final class FrameStream {
        var retouchPool: CVPixelBufferPool?
        var hdrConversionPool: CVPixelBufferPool?

        func resetPools() {
            retouchPool = nil
            hdrConversionPool = nil
        }
    }
    private let recordingStream = FrameStream()
    private let previewStream = FrameStream()

    // Enhanced Stabilization: recordings use the heaviest stabilization, which runs
    // behind real time, so the live preview comes from a second, low-latency stream.
    var enhancedStabilizationEnabled = false
    private let previewOutput = AVCaptureVideoDataOutput()
    private let previewQueue = DispatchQueue(label: "previewQueue")

    // Full-size still photos (the live frames are only 1920x1080, about 2 megapixels)
    private let photoOutput = AVCapturePhotoOutput()
    /// Reports the people, pets and things Cinematic Video is tracking
    private let subjectOutput = AVCaptureMetadataOutput()
    /// What to draw boxes around on the live picture; empty when nothing is tracked
    @Published private(set) var subjectBoxes: [SubjectBox] = []
    /// Photo tab: when each face first showed, so its box can leave again after a moment
    private var faceFirstSeen: [Int: CFTimeInterval] = [:]
    /// Photo tab: a tap is holding the lens focus and brightness on one spot
    private var lensHeldByTap = false
    /// True while a press-and-hold keeps focus and brightness where they are ("AE/AF LOCK"),
    /// until the next tap or a change of camera or tab
    @Published private(set) var focusLocked = false
    /// The same, readable from the camera queues (the published copy lives on the main thread)
    private var lockHeld = false {
        didSet {
            let held = lockHeld
            if Thread.isMainThread { focusLocked = held } else { DispatchQueue.main.async { self.focusLocked = held } }
        }
    }
    private var lockCount = 0
    /// Where the faces the camera sees are right now, in the displayed picture (0...1),
    /// whether or not their boxes are on screen.
    private var latestFaces: [Int: CGRect] = [:]
    /// Video with the blur: the camera's own ID for each of those faces, and when they were last reported
    private var latestFaceIDs: [Int: Int] = [:]
    private var facesSeenAt: CFTimeInterval = 0
    var latestSubjectRects: [CGRect] { Array(latestFaces.values) }
    /// A face the user tapped: its yellow box shows until this time, whatever the camera
    /// itself reports as in focus
    private var tappedFace: Int?
    private var tappedFaceUntil: CFTimeInterval = 0
    /// How much brighter (+) or darker (-) than the camera's own pick, in stops: set by
    /// dragging the sun next to the focus box. 0 = the camera's pick.
    @Published private(set) var brightnessShift: Float = 0
    /// The sun's travel from the middle to either end. An estimate of the iPhone Camera's.
    static let brightnessLimit: Float = 2
    /// Video tab: the boxes show for a moment after something new happens (a face comes
    /// in, focus moves, a tap), then leave, like the iPhone Camera
    private var boxesShownSince: CFTimeInterval = 0
    private var lastFocusedSubject: Int?
    private static let boxesStayFor: CFTimeInterval = 2
    private var sceneChangeWatcher: NSObjectProtocol?
    private let photoQueue = DispatchQueue(label: "photoQueue", qos: .userInitiated)
    private var pendingPhotoCompletion: ((UIImage?) -> Void)?
    /// True from the shutter press until the finished photo is handed back (main thread)
    var isTakingPhoto: Bool { pendingPhotoCompletion != nil }
    /// The live depth map at the shutter press, for a shot that comes without its own depth
    private var shutterDepth: CVPixelBuffer?
    private var askedPhotoPixels = 0
    /// Which shot the waiting completion belongs to
    private var pendingPhotoID: Int64?
    /// How the camera was set at the shutter press. The finished photo arrives up to 2 s
    /// later and must look like the press, not like whatever was changed since.
    private struct ShutterLook {
        let isFront: Bool
        let zoom: CGFloat
        let focusPoint: CGPoint?
        let aperture: Float
        let filter: Filter?
        let filterIntensity: Double
        let mist: Float
    }
    private var shutterLook: ShutterLook?
    /// How bright the live picture is in the Photo tab, noted a few times a second, and
    /// what it was when the shutter was pressed (see matchedToScreen)
    private let liveLevelsLock = NSLock()
    private var liveLevels: (levels: [Float], at: CFTimeInterval, steady: Bool)?
    private var photoStartedAt: CFTimeInterval?
    private var shutterLiveLevels: [Float]?
    /// True while the Photo tab is showing. The background blur (Cinematic) is switched off
    /// then, because with it on the camera only delivers photos of about 3 megapixels.
    private(set) var photoModeActive = false
    /// Slo-mo tab: 120 pictures a second from the plain camera (Cinematic blur stops at 60),
    /// written into the file 4 times slower
    private(set) var slowMoActive = false
    /// The camera really is running at 120 (one without such a format stays ordinary video)
    private var slowMoRunning = false
    private var slowFrameCount = 0
    static let slowMoSpeed = 120
    static let slowMoFactor = 4
    /// Settings > Mirror selfies (on unless switched off): on saves a selfie as the screen
    /// shows it, off saves it the way other people see you. The live picture never changes.
    static var mirrorSelfies: Bool { UserDefaults.standard.object(forKey: "mirrorSelfies") as? Bool ?? true }
    /// How a selfie video's saved frames are flipped back when Mirror selfies is off. A video
    /// filmed sideways is turned by a tag on the file, so its side-to-side is the frame's up-down.
    private enum RecordFlip { case none, sideToSide, upDown }
    private var recordFlip = RecordFlip.none
    /// Mirror selfies was off when this take began (the switch is fixed for the whole take)
    private var takeUnmirrors = false
    /// The Photo tab's background blur (see PortraitBlur). On for the back depth camera and
    /// for the selfie camera.
    private let portraitBlur = PortraitBlur()
    private var photoBlurActive = false
    /// True when the blur is drawn from depth (back camera); false = it follows the person's
    /// outline (selfie camera, which keeps its usual format and photo size that way)
    private var photoBlurUsesDepth = false
    /// The f-number the user picked for Portrait, shared by Photo and Video (each clamps it
    /// to its own range). Remembered between launches.
    private var chosenAperture = (UserDefaults.standard.object(forKey: "portraitAperture") as? NSNumber)?.floatValue
        ?? CameraManager.portraitAperture
    /// The value this class last put on the slider itself (main thread only)
    private var shownAperture: Float?
    /// Where a tap set the focus in the Photo tab (displayed picture, normalized, origin
    /// top-left); nil = the middle of the picture
    private var photoFocusPoint: CGPoint?
    private let depthQueue = DispatchQueue(label: "depthQueue")
    /// True when previewOutput is in the session and drives the preview
    private(set) var usesSeparatePreviewStream = false
    private var hasLoggedPreviewStabilization = false
    private var isObservingSessionErrors = false
    private var currentVideoSize = CGSize(width: 1080, height: 1920)
    private var retouchEnabled = false

    // HDR (10-bit HLG). hdrEnabled is the user's choice; isHDRActive is what the
    // active camera format actually delivers.
    var hdrEnabled = false
    // Video size and speed. The "wanted" pair is the user's choice ("4K · 60"); the "active"
    // pair is what the camera in use really runs at (the selfie blur camera stops at 30).
    var wantsFourK = false
    /// What each camera wants; the flip button switches to the other camera's size and speed
    var frontFormat: (fourK: Bool, frameRate: Int) = (false, 30)
    var backFormat: (fourK: Bool, frameRate: Int) = (true, 30)
    var wantedFrameRate = 30
    @Published private(set) var activeFourK = false
    @Published private(set) var activeFrameRate = 30
    /// False on a camera that cannot do 60 in its current setup (selfie with blur)
    @Published private(set) var sixtyAvailable = false
    private(set) var isHDRActive = false
    private var hdrMTIContext: MTIContext?
    private let hlgColorSpace = CGColorSpace(name: CGColorSpace.itur_2100_HLG)

    // Face detection for targeted smoothing
    private var cachedFaceBounds: CGRect?
    private var faceDetectionCounter = 0
    private let faceDetectionInterval = 10  // Run detection every N frames
    private let faceDetectionQueue = DispatchQueue(label: "faceDetectionQueue", qos: .userInitiated)

    // Adjustable retouch parameters
    var retouchAmount: Float = 0.5         // Smoothing intensity (0.0 - 1.0)
    /// The Mist slider, 0 (off) to 1. See `applyMist`.
    var mistAmount: Float = 0
    /// How strong the glow is with the slider at the top ("strong" on the sample sheet)
    static let mistFullStrength = 1.3
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
        var attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: isHDRActive ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        if isHDRActive {
            // Tag every recording buffer as BT.2020 / HLG so Core Image encodes it correctly
            attributes[kCVBufferPropagatedAttachmentsKey as String] = [
                kCVImageBufferColorPrimariesKey as String: kCVImageBufferColorPrimaries_ITU_R_2020,
                kCVImageBufferTransferFunctionKey as String: kCVImageBufferTransferFunction_ITU_R_2100_HLG,
                kCVImageBufferYCbCrMatrixKey as String: kCVImageBufferYCbCrMatrix_ITU_R_2020
            ]
        }
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pixelBufferPool)
    }

    private func getCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInUltraWideCamera, .builtInTrueDepthCamera, .builtInWideAngleCamera]
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: position).devices

        // Prefer a camera that supports the native Cinematic (bokeh) effect
        if #available(iOS 26.0, *),
           let cinematicCamera = devices.first(where: { $0.formats.contains { $0.isCinematicVideoCaptureSupported } }) {
            return cinematicCamera
        }
        return devices.first
    }

    /// The back camera that delivers a depth map with every photo (the LiDAR one). The Photo
    /// tab uses it for its background blur: it shows the same view as the main camera and
    /// takes the same size of photo (measured on iPhone 18 Pro Max: 73.3 degrees, 4224x2376).
    /// nil on phones without it.
    private lazy var backDepthCamera: AVCaptureDevice? = {
        guard backAllLensCamera != nil,
              let camera = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInLiDARDepthCamera], mediaType: .video,
                                                            position: .back).devices.first,
              depthFormat(on: camera) != nil else { return nil }
        return camera
    }()

    /// The camera format the Photo tab's blur needs on a back camera: the whole 4:3 sensor,
    /// like the iPhone Camera's Photo mode, that comes with depth. The selfie camera has depth
    /// only in its square-sensor format, which shows 20% more than the Photo tab's selfie view;
    /// trimming it back would cost detail, so the selfie blur works without depth (measured on
    /// iPhone 18 Pro Max).
    private func depthFormat(on device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        guard device.position == .back else { return nil }
        return Self.bestPhotoFormat(in: device.formats.filter { !$0.supportedDepthDataFormats.isEmpty },
                                    limit: photoPixelLimit)
    }

    /// Photos go up to about 24 MP, what the iPhone Camera saves by default on 48 MP phones
    private static let bigPhotoPixels = 25_000_000
    private static let standardPhotoPixels = 12_500_000
    /// Set when a camera was asked for a photo over 12 MP and handed over 12 anyway (Apple's
    /// notes say some iPhones only give 24 MP through their own delayed processing, which our
    /// filters can't follow). The Photo tab then goes back to the 12 MP setup, where the photo
    /// brings its own depth for the blur.
    private var bigPhotosRefused = false
    private var photoPixelLimit: Int { bigPhotosRefused ? Self.standardPhotoPixels : Self.bigPhotoPixels }

    /// The biggest photo a format takes within `limit` pixels. Measured on iPhone 18 Pro Max
    /// (2026-11-15): the depth camera's 4032x3024 format gives 5712x4284 (24 MP) in about 2 s,
    /// but only when the shot does not ask for depth; with depth it comes back at 4032x3024.
    /// The all-lens camera (.5x, 2x...) hands over 4032x3024 from the same format, so it keeps
    /// its lighter 1920x1440 one. The front camera's square format lists 4896x4896 and hands
    /// over 3024x4032; its 18 MP (3672x4896) only comes through Apple's delayed processing
    /// (autoDeferredPhotoDelivery), which finishes the photo in the library without our look.
    private static func photoPixels(_ format: AVCaptureDevice.Format, limit: Int) -> Int {
        format.supportedMaxPhotoDimensions.map { Int($0.width) * Int($0.height) }
            .filter { $0 <= limit }.max() ?? 0
    }

    /// Of the 8-bit 4:3 formats given, the one that takes the biggest photo. Between equals,
    /// the one with the smallest live picture (not under 1920 wide), which is lighter to show.
    private static func bestPhotoFormat(in formats: [AVCaptureDevice.Format], limit: Int) -> AVCaptureDevice.Format? {
        func width(_ format: AVCaptureDevice.Format) -> Int32 {
            CMVideoFormatDescriptionGetDimensions(format.formatDescription).width
        }
        let usable = formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width * 3 == dimensions.height * 4 && dimensions.width >= 1920
                && CMFormatDescriptionGetMediaSubType(format.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
        }
        return usable.max { first, second in
            let (firstPhoto, secondPhoto) = (photoPixels(first, limit: limit), photoPixels(second, limit: limit))
            return firstPhoto != secondPhoto ? firstPhoto < secondPhoto : width(first) > width(second)
        }
    }

    /// The camera that gives a position its background blur in the current tab.
    private func blurCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back, photoModeActive, let depthCamera = backDepthCamera { return depthCamera }
        return getCamera(for: position)
    }

    /// Picks the capture format (SDR or HDR) and, when `enableCinematic` is true, turns on
    /// Apple's native Cinematic Video (depth-of-field bokeh). Frames then arrive at
    /// videoOutput with the bokeh already applied, so retouch and filters stack on top
    /// of it. Call after the input and outputs are in the session.
    /// The 8-bit 1920x1080 format made for 120 pictures a second (not the 240 one, which
    /// gives up picture quality for speed), if this camera has one
    private func slowMoFormat(on device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        func topSpeed(_ format: AVCaptureDevice.Format) -> Double {
            format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        }
        let fast = device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let subType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let is8Bit = subType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                || subType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            return dimensions.width == 1920 && dimensions.height == 1080 && is8Bit
                && topSpeed(format) >= Double(Self.slowMoSpeed)
        }
        return fast.first { topSpeed($0) < Double(Self.slowMoSpeed) + 1 } ?? fast.first
    }

    private func configureFormatAndCinematic(on input: AVCaptureDeviceInput, enableCinematic: Bool) {
        guard #available(iOS 26.0, *) else { return }
        // Subject tracking is asked for again once the camera is set up (every way out of here)
        if captureSession.outputs.contains(subjectOutput) { subjectOutput.metadataObjectTypes = [] }
        defer { updateSubjectTracking(for: input) }
        // Hide the f-stop slider until Cinematic is confirmed on this camera
        DispatchQueue.main.async { self.apertureRange = nil }
        let device = input.device
        let cinematicFormats = device.formats.filter { $0.isCinematicVideoCaptureSupported }
        isHDRActive = false
        slowMoRunning = false

        // Photo tab: a format that delivers depth with the photo, for the background blur
        if photoModeActive, !usesAllLenses, let format = depthFormat(on: device) {
            if input.isCinematicVideoCaptureEnabled { input.isCinematicVideoCaptureEnabled = false }
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                captureSession.automaticallyConfiguresCaptureDeviceForWideColor = false
                if format.supportedColorSpaces.contains(.sRGB) { device.activeColorSpace = .sRGB }
                device.unlockForConfiguration()
            } catch {
                print("Failed to set the depth format: \(error.localizedDescription)")
            }
            return
        }

        // Slo-mo tab: the plain 1080p format that reaches 120 pictures a second
        if slowMoActive, !photoModeActive, let format = slowMoFormat(on: device) {
            if input.isCinematicVideoCaptureEnabled { input.isCinematicVideoCaptureEnabled = false }
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                let frameTime = CMTime(value: 1, timescale: CMTimeScale(Self.slowMoSpeed))
                device.activeVideoMinFrameDuration = frameTime
                device.activeVideoMaxFrameDuration = frameTime
                captureSession.automaticallyConfiguresCaptureDeviceForWideColor = false
                if format.supportedColorSpaces.contains(.sRGB) { device.activeColorSpace = .sRGB }
                device.unlockForConfiguration()
                slowMoRunning = true
                print("Slo-mo format: \(device.localizedName) 1920x1080 at \(Self.slowMoSpeed) fps")
                DispatchQueue.main.async {
                    self.activeFourK = false
                    self.activeFrameRate = Self.slowMoSpeed
                    self.sixtyAvailable = false
                }
                return
            } catch {
                print("Failed to set the slo-mo format: \(error.localizedDescription)")
            }
        }

        // A camera with no Cinematic formats (the back camera with all the lenses) gets an
        // ordinary 30/60 fps video format: 8-bit for SDR, 10-bit HLG for HDR. It has to be
        // picked by hand, because the session stops choosing once any format was set.
        let candidates = !cinematicFormats.isEmpty ? cinematicFormats : device.formats.filter { format in
            let subType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let is8Bit = subType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                || subType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            let isHLG = subType == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                && format.supportedColorSpaces.contains(.HLG_BT2020)
            return (is8Bit || isHLG)
                && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 && $0.maxFrameRate <= 60 }
        }

        // Landscape 1080p only: portrait-native formats would break the .right rotation
        // The front camera's 16:9 formats come out about 12% too wide when Cinematic is off,
        // which made faces look stretched in the Photo tab. Its 4:3 format has true proportions
        // (and gives 12 MP stills), so the Photo tab uses that one.
        // The back camera's Photo tab is 4:3 too, like the iPhone Camera's Photo mode.
        let wantsFourByThree = (!enableCinematic && device.position == .front)
            || (photoModeActive && device.position == .back)
        let pool = wantsFourByThree ? device.formats : candidates
        func landscape(width: Int32, height: Int32) -> [AVCaptureDevice.Format] {
            pool.filter {
                let dimensions = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                // Exactly this shape: the all-lens camera also lists a 1440x1080 (4:3) format first
                return dimensions.width == width && dimensions.height == height
            }
        }
        func topSpeed(_ format: AVCaptureDevice.Format) -> Int {
            Int((format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30).rounded())
        }
        var landscape1080 = landscape(width: 1920, height: wantsFourByThree ? 1440 : 1080)
        var speed: Int?
        var canDoSixty = false
        if !wantsFourByThree {
            // Video: the size and speed picked on the camera screen. Real 4K frames from the
            // camera when it has them; a camera that stops at 30 (selfie blur) stays at 30.
            let fourK = wantsFourK ? landscape(width: 3840, height: 2160) : []
            let sized = fourK.isEmpty ? landscape1080 : fourK
            canDoSixty = sized.contains { topSpeed($0) >= 60 }
            // The format made for the wanted speed first, then a faster one slowed down
            let exact = sized.filter { topSpeed($0) == wantedFrameRate }
            let faster = sized.filter { topSpeed($0) > wantedFrameRate }
            landscape1080 = !exact.isEmpty ? exact : !faster.isEmpty ? faster : sized
        }
        // HDR: the 10-bit format that supports HLG. SDR: the 8-bit format, as before.
        let hdrFormat = hdrEnabled ? landscape1080.first { $0.supportedColorSpaces.contains(.HLG_BT2020) } : nil
        guard let format = hdrFormat
                ?? landscape1080.first(where: { !$0.supportedColorSpaces.contains(.HLG_BT2020) })
                ?? cinematicFormats.first else {
            print("Cinematic video not supported on this camera")
            return
        }
        let useHDR = hdrFormat != nil
        if !wantsFourByThree { speed = min(wantedFrameRate, topSpeed(format)) }
        let formatWidth = CMVideoFormatDescriptionGetDimensions(format.formatDescription).width
        DispatchQueue.main.async {
            self.activeFourK = formatWidth >= 3840
            self.activeFrameRate = speed ?? 30
            self.sixtyAvailable = canDoSixty
        }

        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            if let speed {
                let frameTime = CMTime(value: 1, timescale: CMTimeScale(speed))
                device.activeVideoMinFrameDuration = frameTime
                device.activeVideoMaxFrameDuration = frameTime
                print("Video format: \(formatWidth) wide at \(speed) fps")
            }
            // Set the color space ourselves; the session would otherwise pick it
            captureSession.automaticallyConfiguresCaptureDeviceForWideColor = false
            device.activeColorSpace = useHDR ? .HLG_BT2020 : .sRGB
            device.unlockForConfiguration()
        } catch {
            print("Failed to set Cinematic format: \(error.localizedDescription)")
            return
        }
        isHDRActive = useHDR
        if hdrEnabled && !useHDR {
            print("HDR requested but this camera has no HLG Cinematic format; using SDR")
        }

        guard enableCinematic else {
            if input.isCinematicVideoCaptureEnabled {
                input.isCinematicVideoCaptureEnabled = false
            }
            print("Cinematic off: \(device.localizedName), HDR=\(useHDR)")
            return
        }
        guard input.isCinematicVideoCaptureSupported else {
            print("Cinematic video not supported in this session configuration")
            return
        }
        input.isCinematicVideoCaptureEnabled = true
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        print("Cinematic video enabled: \(device.localizedName) \(dimensions.width)x\(dimensions.height), f/\(input.simulatedAperture), HDR=\(useHDR)")

        // minSimulatedAperture is 0 when the format has no adjustable aperture
        guard format.minSimulatedAperture > 0 else { return }
        let range = format.minSimulatedAperture...format.maxSimulatedAperture
        // Portrait off = the weakest blur Cinematic has
        let aperture = portraitOn ? min(max(chosenAperture, range.lowerBound), range.upperBound) : range.upperBound
        input.simulatedAperture = aperture
        print("Cinematic aperture range: f/\(range.lowerBound) - f/\(range.upperBound)")
        DispatchQueue.main.async {
            self.apertureRange = range
            self.shownAperture = aperture
            self.simulatedAperture = aperture
        }
    }

    /// Sets video stabilization on each video stream. Call after configureFormatAndCinematic,
    /// since that can change the active format.
    private func enableStabilization() {
        guard let format = currentVideoInput?.device.activeFormat else { return }

        var lowLatencyModes: [AVCaptureVideoStabilizationMode] = [.standard]
        if #available(iOS 26.0, *) {
            // Selfie 4K with the blur on: the low-latency mode leaves the face soft there
            // (eyes blurred while clothes stay sharp, measured on an iPhone 18 Pro Max).
            // The standard mode keeps it sharp with the same framing. 1080p is fine either way.
            let softensFace = currentVideoInput?.device.position == .front
                && currentVideoInput?.isCinematicVideoCaptureEnabled == true
                && CMVideoFormatDescriptionGetDimensions(format.formatDescription).width >= 3840
            if !softensFace { lowLatencyModes.insert(.lowLatency, at: 0) }
        }

        if usesSeparatePreviewStream {
            // Recording: heaviest smoothing. It runs behind real time, which the
            // recorder handles with timestamps; the preview stream stays instant.
            var recordingModes: [AVCaptureVideoStabilizationMode] = [.cinematicExtended, .cinematic, .standard]
            if #available(iOS 18.0, *) {
                recordingModes.insert(.cinematicExtendedEnhanced, at: 0)
            }
            applyStabilization(to: videoOutput, preferring: recordingModes, format: format, label: "recording")
            var previewModes = lowLatencyModes
            if #available(iOS 17.0, *) {
                previewModes.insert(.previewOptimized, at: 0)
            }
            applyStabilization(to: previewOutput, preferring: previewModes, format: format, label: "preview")
        } else {
            // One stream drives both preview and recording, so avoid the cinematic modes:
            // they buffer frames ahead and delayed the live preview by seconds.
            applyStabilization(to: videoOutput, preferring: lowLatencyModes, format: format, label: "video")
        }
        hasLoggedStabilization = false
        hasLoggedPreviewStabilization = false
    }

    private func applyStabilization(to output: AVCaptureVideoDataOutput,
                                    preferring modes: [AVCaptureVideoStabilizationMode],
                                    format: AVCaptureDevice.Format,
                                    label: String) {
        guard let connection = output.connection(with: .video),
              connection.isVideoStabilizationSupported else {
            print("Video stabilization not supported (\(label))")
            return
        }
        guard let mode = modes.first(where: { format.isVideoStabilizationModeSupported($0) }) else {
            print("No supported stabilization mode (\(label))")
            return
        }
        connection.preferredVideoStabilizationMode = mode
    }

    private func stabilizationName(_ mode: AVCaptureVideoStabilizationMode) -> String {
        if #available(iOS 18.0, *), mode == .cinematicExtendedEnhanced {
            return "cinematicExtendedEnhanced"
        }
        if #available(iOS 26.0, *), mode == .lowLatency {
            return "lowLatency"
        }
        if #available(iOS 17.0, *), mode == .previewOptimized {
            return "previewOptimized"
        }
        switch mode {
        case .off: return "off"
        case .standard: return "standard"
        case .cinematic: return "cinematic"
        case .cinematicExtended: return "cinematicExtended"
        default: return "other (\(mode.rawValue))"
        }
    }

    private var currentVideoInput: AVCaptureDeviceInput? {
        captureSession.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first { $0.device.hasMediaType(.video) }
    }

    /// Sets the Cinematic blur strength. Clamped to the camera's range, since an
    /// out-of-range value throws NSRangeException.
    func setSimulatedAperture(_ value: Float) {
        guard portraitOn else { return }
        // The slider also reports the value this class put on it after a tab or camera
        // change (the pick fitted to that camera's range): that is not a new pick
        let shown = shownAperture
        shownAperture = nil
        if value == shown { return }
        chosenAperture = value
        UserDefaults.standard.set(value, forKey: "portraitAperture")
        applyAperture()
    }

    /// Photo draws its own blur from chosenAperture, so only Video has something to set here.
    private func applyAperture() {
        guard !photoBlurActive, #available(iOS 26.0, *), let range = apertureRange,
              let input = currentVideoInput,
              input.isCinematicVideoCaptureEnabled else { return }
        input.simulatedAperture = portraitOn
            ? min(max(chosenAperture, range.lowerBound), range.upperBound) : range.upperBound
    }

    /// The sun slider: makes the picture brighter or darker than the camera's own pick.
    /// Stays until the next tap, a change of camera or tab, or (Photo) a new scene.
    func setBrightnessShift(_ stops: Float) {
        guard let device = currentVideoInput?.device else { return }
        let limit = Self.brightnessLimit
        let lowest = max(-limit, device.minExposureTargetBias)
        let highest = min(limit, device.maxExposureTargetBias)
        // Steps of 1/20 stop: fine enough to look smooth, without a camera call per pixel
        let wanted = min(max((stops * 20).rounded() / 20, lowest), highest)
        guard wanted != brightnessShift, (try? device.lockForConfiguration()) != nil else { return }
        device.setExposureTargetBias(wanted, completionHandler: nil)
        device.unlockForConfiguration()
        brightnessShift = wanted
    }

    /// Back to the camera's own brightness
    private func resetBrightnessShift(on device: AVCaptureDevice) {
        guard brightnessShift != 0 else { return }
        // Shown on screen, so it changes on the main thread (camera changes call this off it)
        if Thread.isMainThread { brightnessShift = 0 } else { DispatchQueue.main.async { self.brightnessShift = 0 } }
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.setExposureTargetBias(0, completionHandler: nil)
        device.unlockForConfiguration()
    }

    /// Press and hold, like the iPhone Camera's AE/AF LOCK: focus and brightness go to the
    /// spot and stay there (no more hunting in the middle of a video) until the next tap.
    /// The sun slider still works while locked.
    func lockFocusAndBrightness(atDisplayPoint point: CGPoint) {
        // First the same as a tap: focus (and in Photo the brightness) goes to the spot
        setCinematicFocus(atDisplayPoint: point)
        guard let input = currentVideoInput else { return }
        let device = input.device
        let full = CGPoint(x: 0.5 + (point.x - 0.5) / digitalZoom, y: 0.5 + (point.y - 0.5) / digitalZoom)
        let devicePoint = currentPosition == .front
            ? CGPoint(x: full.y, y: full.x)
            : CGPoint(x: full.y, y: 1 - full.x)
        guard (try? device.lockForConfiguration()) != nil else { return }
        if #available(iOS 26.0, *), input.isCinematicVideoCaptureEnabled {
            // Fixed = focus stays at this distance instead of following the subject
            device.setCinematicVideoFixedFocus(at: devicePoint, focusMode: .strong)
            if device.isExposurePointOfInterestSupported,
               device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .continuousAutoExposure
            }
        } else {
            // Photo: the lens is already held on the spot; a new scene must not release it
            device.isSubjectAreaChangeMonitoringEnabled = false
        }
        device.unlockForConfiguration()
        lockCount += 1
        let lock = lockCount
        lockHeld = true
        // The brightness is frozen once it has settled on the spot
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.lockHeld, self.lockCount == lock,
                  device == self.currentVideoInput?.device,
                  device.isExposureModeSupported(.locked),
                  (try? device.lockForConfiguration()) != nil else { return }
            device.exposureMode = .locked
            device.unlockForConfiguration()
        }
    }

    /// Ends a press-and-hold lock: the camera picks the brightness again
    private func unlockFocusAndBrightness(on device: AVCaptureDevice) {
        guard lockHeld else { return }
        lockHeld = false
        lockCount += 1
        guard (try? device.lockForConfiguration()) != nil else { return }
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.unlockForConfiguration()
    }

    /// Photo tab: points the real lens focus and the brightness at a tapped spot, like the
    /// iPhone Camera, and lets go again once the scene changes.
    private func holdLens(at point: CGPoint) {
        guard let input = currentVideoInput else { return }
        // Changing the focus mode while Cinematic Video is on is a crash
        if #available(iOS 26.0, *), input.isCinematicVideoCaptureEnabled { return }
        // Same turn (and selfie mirror) as the Cinematic mapping below
        let devicePoint = currentPosition == .front
            ? CGPoint(x: point.y, y: point.x)
            : CGPoint(x: point.y, y: 1 - point.x)
        let device = input.device
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported,
               device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .continuousAutoExposure
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        } catch {
            print("Failed to set focus point: \(error.localizedDescription)")
            return
        }
        lensHeldByTap = true
        subjectBoxes = []
        if sceneChangeWatcher == nil {
            sceneChangeWatcher = NotificationCenter.default.addObserver(
                forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard let self, let device = note.object as? AVCaptureDevice,
                      device == self.currentVideoInput?.device else { return }
                self.resetBrightnessShift(on: device)
                self.releaseLens(on: device)
            }
        }
    }

    /// Hands focus and brightness back to the camera (whole picture, faces first)
    private func releaseLens(on device: AVCaptureDevice) {
        guard lensHeldByTap else { return }
        lensHeldByTap = false
        // Read while faces are drawn, on the main thread
        if Thread.isMainThread { faceFirstSeen = [:] } else { DispatchQueue.main.async { self.faceFirstSeen = [:] } }
        if #available(iOS 26.0, *), currentVideoInput?.isCinematicVideoCaptureEnabled == true { return }
        guard (try? device.lockForConfiguration()) != nil else { return }
        let middle = CGPoint(x: 0.5, y: 0.5)
        if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = middle }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = middle }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.isSubjectAreaChangeMonitoringEnabled = false
        device.unlockForConfiguration()
    }

    /// Asks the camera for the subjects Cinematic Video tracks, which it must be given
    /// while Cinematic is on. Outside Cinematic there is nothing to track, so no boxes.
    @available(iOS 26.0, *)
    private func updateSubjectTracking(for input: AVCaptureDeviceInput) {
        guard captureSession.outputs.contains(subjectOutput) else { return }
        var types: [AVMetadataObject.ObjectType] = []
        if input.isCinematicVideoCaptureEnabled {
            let wanted = subjectOutput.requiredMetadataObjectTypesForCinematicVideoCapture
            let offered = Set(subjectOutput.availableMetadataObjectTypes)
            // Asking for a kind the camera does not offer is a crash
            if wanted.allSatisfy(offered.contains) { types = wanted }
        } else if photoModeActive, subjectOutput.availableMetadataObjectTypes.contains(.face) {
            // Photo tab: faces only, for the box that shows when one is found
            types = [.face]
        }
        subjectOutput.metadataObjectTypes = types
        if types.isEmpty { DispatchQueue.main.async { self.subjectBoxes = [] } }
    }

    /// The camera's own ID for the face under a tap (a point in the displayed picture),
    /// when Cinematic has just reported one there
    private func cinematicFace(at point: CGPoint) -> Int? {
        guard CACurrentMediaTime() - facesSeenAt < 1 else { return nil }
        // A little room around the box: a tap on the hair or chin still means that person
        let hits = latestFaces.filter {
            $0.value.insetBy(dx: -$0.value.width * 0.15, dy: -$0.value.height * 0.15).contains(point)
        }
        let nearest = hits.min { $0.value.width * $0.value.height < $1.value.width * $1.value.height }
        return nearest.flatMap { latestFaceIDs[$0.key] }
    }

    /// Moves Cinematic focus to the subject at a point in the displayed image
    /// (portrait, normalized 0...1, origin top-left), and keeps tracking it.
    func setCinematicFocus(atDisplayPoint point: CGPoint) {
        // A new tap starts from the camera's own brightness, like the iPhone Camera, and
        // ends a press-and-hold lock
        if let device = currentVideoInput?.device {
            unlockFocusAndBrightness(on: device)
            resetBrightnessShift(on: device)
        }
        // A tap on a face brings its yellow box back for a moment
        tappedFace = latestFaces.first { $0.value.contains(point) }?.key
        let faceUnderTap = cinematicFace(at: point)
        tappedFaceUntil = CACurrentMediaTime() + Self.boxesStayFor
        // Cinematic focus only exists while the background blur is running
        var blurRunning = false
        if #available(iOS 26.0, *) { blurRunning = currentVideoInput?.isCinematicVideoCaptureEnabled == true }
        if photoModeActive || !blurRunning {
            // Photo tab, and video without the blur (slo-mo, Enhanced Stabilization, the zoom
            // levels on the other lenses): the real lens goes to the spot in the full, un-zoomed picture
            let shownShare = digitalZoom
            let full = CGPoint(x: 0.5 + (point.x - 0.5) / shownShare,
                               y: 0.5 + (point.y - 0.5) / shownShare)
            // The background blur keeps this spot sharp (the selfie blur always keeps
            // the person sharp instead)
            if photoBlurUsesDepth { photoFocusPoint = full }
            holdLens(at: full)
            return
        }
        guard #available(iOS 26.0, *), let input = currentVideoInput,
              input.isCinematicVideoCaptureEnabled else { return }

        // Digital zoom shows only the centre of the frame; map the tap back to the full frame
        let point = CGPoint(x: 0.5 + (point.x - 0.5) / digitalZoom,
                            y: 0.5 + (point.y - 0.5) / digitalZoom)

        // The display is the landscape sensor buffer rotated 90° clockwise (.right),
        // and mirrored on the front camera. Undo both to get device coordinates.
        let devicePoint = currentPosition == .front
            ? CGPoint(x: point.y, y: point.x)
            : CGPoint(x: point.y, y: 1 - point.x)

        let device = input.device
        do {
            try device.lockForConfiguration()
            // .strong keeps the subject in focus until it leaves the frame.
            // A tap on a face the camera has found follows that face itself. Pointing at the
            // spot instead made the camera invent a new subject there (a patch of skin, or at
            // 4K the whole picture) and hold on to that, which left the face soft.
            if let faceUnderTap, WriterGuard.attempt({
                device.setCinematicVideoTrackingFocus(detectedObjectID: faceUnderTap, focusMode: .strong)
            }) {
                print("Cinematic focus set on face \(faceUnderTap)")
            } else {
                device.setCinematicVideoTrackingFocus(at: devicePoint, focusMode: .strong)
                print("Cinematic focus set at device point (\(String(format: "%.2f", devicePoint.x)), \(String(format: "%.2f", devicePoint.y)))")
            }
            device.unlockForConfiguration()
            // Bring the boxes back to show where focus went
            boxesShownSince = CACurrentMediaTime()
        } catch {
            print("Failed to set Cinematic focus: \(error.localizedDescription)")
        }
    }

    // MARK: - Zoom

    /// The camera's raw zoom factor times this gives the number the Camera app shows
    /// (a dual-lens back camera's raw 1.0 is the ultra-wide lens, shown as 0.5x).
    private func zoomDisplayMultiplier(for device: AVCaptureDevice) -> CGFloat {
        if #available(iOS 18.0, *) { return device.displayVideoZoomFactorMultiplier }
        return 1
    }

    /// Where this phone's telephoto lens starts, as the Camera app shows it (4 on a
    /// phone with a 4x lens), read from the phone's own lens list. nil = no telephoto.
    private lazy var backTelephotoZoom: CGFloat? = {
        guard #available(iOS 18.0, *),
              let triple = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTripleCamera], mediaType: .video,
                                                            position: .back).devices.first,
              let lastSwitch = triple.virtualDeviceSwitchOverVideoZoomFactors.last else { return nil }
        return CGFloat(truncating: lastSwitch) * triple.displayVideoZoomFactorMultiplier
    }()

    /// The back camera with every lens (ultra-wide, main, telephoto). Apple's blur only
    /// runs on the single main lens (measured on iPhone 18 Pro Max: no other back camera
    /// has a Cinematic format), so zooming out to .5 or in to the telephoto swaps to this
    /// camera and the blur stops there: the same trade as the Camera app's Video mode
    /// versus its Cinematic mode. nil when the blur camera already has every lens, or
    /// when this phone has no blur at all.
    private lazy var backAllLensCamera: AVCaptureDevice? = {
        guard #available(iOS 26.0, *), let blurCamera = getCamera(for: .back),
              blurCamera.formats.contains(where: { $0.isCinematicVideoCaptureSupported }) else { return nil }
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera]
        let allLens = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video,
                                                       position: .back).devices.first
        return allLens?.uniqueID == blurCamera.uniqueID ? nil : allLens
    }()

    /// Which back camera a zoom level calls for: true = all lenses (no blur), false =
    /// the blur camera, nil = stay on the current one. The gap between the two answers
    /// keeps a pinch that hovers at the edge from swapping back and forth.
    private func wantsAllLenses(at zoom: CGFloat) -> Bool? {
        guard currentPosition == .back, !isRecordingActive, backAllLensCamera != nil else { return nil }
        // Only the main lens films at slo-mo speed
        if slowMoActive { return false }
        // Photo tab: the depth camera's lens can't zoom, so from the "2" button up the
        // all-lens camera takes over and the photo stays full size (without blur)
        let photoLimit: CGFloat = photoModeActive && backDepthCamera != nil ? 2 : .infinity
        let telephoto = min(backTelephotoZoom ?? .infinity, photoLimit)
        if zoom <= 0.95 || zoom >= telephoto - 0.01 { return true }
        if zoom >= 1, zoom <= telephoto * 0.9 { return false }
        return nil
    }

    /// Lowest zoom offered, as shown on screen. On the back that is the ultra-wide lens
    /// of the all-lens camera, even while the blur camera is the one in use.
    private func minDisplayZoom(for device: AVCaptureDevice) -> CGFloat {
        let widest = device.position == .back && !slowMoActive ? (backAllLensCamera ?? device) : device
        return widest.minAvailableVideoZoomFactor * zoomDisplayMultiplier(for: widest)
    }

    /// Highest zoom offered, as shown on screen. Back: up to twice the telephoto step
    /// (the Camera app's last button), or 6x on phones without one. Cinematic blur
    /// locks the front lens (range 1.0-1.0 on iPhone 18 Pro Max), so zoom there is done
    /// by cropping; that is held to 2x of the lens's own view to stay sharp.
    private func maxDisplayZoom(for device: AVCaptureDevice) -> CGFloat {
        let minRaw = device.minAvailableVideoZoomFactor
        // Slo-mo stays on one lens, so zoom is a crop: held to 2x to stay sharp
        if slowMoActive { return minRaw * zoomDisplayMultiplier(for: device) * 2 }
        let lensCanZoom = device.maxAvailableVideoZoomFactor > minRaw + 0.01
        // (The back depth camera's lens is locked too, but the all-lens camera takes over
        // from it, so the back keeps its full row of buttons.)
        let allLensTakesOver = device.position == .back && backAllLensCamera != nil
        guard lensCanZoom || allLensTakesOver else { return minRaw * zoomDisplayMultiplier(for: device) * 2 }
        guard device.position == .back, let telephoto = backTelephotoZoom else { return 6 }
        return max(6, telephoto * 2)
    }

    /// The zoom buttons for a camera, like the Camera app's row: ultra-wide (when this
    /// mode allows it), 1, 2, then the telephoto step and its double on the back.
    private func zoomPresets(for device: AVCaptureDevice) -> [CGFloat] {
        let minDisplay = minDisplayZoom(for: device)
        var presets: [CGFloat] = (minDisplay < 0.95 ? [minDisplay] : []) + [1, 2]
        if device.position == .back, let telephoto = backTelephotoZoom {
            presets += [telephoto, telephoto * 2]
        }
        let maxDisplay = maxDisplayZoom(for: device)
        var result: [CGFloat] = []
        for preset in presets.sorted() where preset <= maxDisplay + 0.01 && preset != result.last {
            result.append(preset)
        }
        return result
    }

    /// Starts a camera at 1x (its main lens), like the Camera app, and publishes the
    /// zoom buttons it supports. Call after any camera or format change, since both
    /// reset the zoom.
    private func resetZoom(for device: AVCaptureDevice, to zoom: CGFloat? = nil) {
        // The selfie camera always starts on its widest view, in both tabs: nobody wants a
        // selfie that starts zoomed in on the face
        let isFront = device.position == .front
        let zoom = zoom ?? (isFront ? minDisplayZoom(for: device) : nil)
        let multiplier = zoomDisplayMultiplier(for: device)
        let minRaw = device.minAvailableVideoZoomFactor
        let rawZoom = min(max((zoom ?? 1) / multiplier, minRaw), device.maxAvailableVideoZoomFactor)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = rawZoom
            device.unlockForConfiguration()
        } catch {
            print("Failed to reset zoom: \(error.localizedDescription)")
        }
        // A plain reset shows whatever the lens gives; a landing zoom the lens can't
        // reach is finished by cropping, as in setDisplayZoom.
        let lensZoom = rawZoom * multiplier
        let shownZoom = max(zoom ?? lensZoom, lensZoom)
        digitalZoom = max(1, shownZoom / lensZoom)
        let presets = zoomPresets(for: device)
        if isFront { print("Selfie view: showing \(shownZoom) (widest \(minDisplayZoom(for: device)))") }
        DispatchQueue.main.async {
            self.zoomPresets = presets
            self.displayZoom = shownZoom
            self.isFrontCamera = isFront
        }
    }

    /// Zooms to a level as shown on screen (1.0 = main lens). The lens does as much as
    /// the current camera and mode allow (out-of-range values would throw); anything
    /// beyond that is done by cropping the picture. `animated` glides like a button tap.
    func setDisplayZoom(_ zoom: CGFloat, animated: Bool = false) {
        guard !isSwitchingCamera, let device = currentVideoInput?.device else { return }
        let target = min(max(zoom, minDisplayZoom(for: device)), maxDisplayZoom(for: device))

        // .5 and the telephoto steps need the back camera's other lenses (and lose the blur)
        if let allLenses = wantsAllLenses(at: target), allLenses != usesAllLenses,
           let camera = allLenses ? backAllLensCamera : blurCamera(for: .back) {
            beginCameraChange()
            if allLenses { isBlurOffForZoom = true }
            Self.sessionSetupQueue.async { [weak self] in
                self?.replaceVideoInput(with: camera, position: .back, allLenses: allLenses,
                                        zoom: target, clearPreview: false)
            }
            return
        }

        let multiplier = zoomDisplayMultiplier(for: device)
        let minRaw = device.minAvailableVideoZoomFactor
        let maxRaw = device.maxAvailableVideoZoomFactor
        let rawZoom = min(max(target / multiplier, minRaw), maxRaw)
        do {
            try device.lockForConfiguration()
            if animated {
                device.ramp(toVideoZoomFactor: rawZoom, withRate: 8)
            } else {
                device.videoZoomFactor = rawZoom
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to set zoom: \(error.localizedDescription)")
            return
        }
        // The blur camera can't go wider than its own lens (e.g. .5 while recording)
        let lensZoom = rawZoom * multiplier
        let shownZoom = max(target, lensZoom)
        digitalZoom = max(1, shownZoom / lensZoom)
        displayZoom = shownZoom
    }

    func configure() {
        guard let camera = getCamera(for: .front) else { return }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: camera)
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
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        } else {
            print("Photo output not supported; photos will use the video frame")
        }

        if captureSession.canAddOutput(subjectOutput) {
            captureSession.addOutput(subjectOutput)
            subjectOutput.setMetadataObjectsDelegate(self, queue: .main)
        }

        // No depth output: AVCaptureDepthDataOutput can't run alongside Cinematic Video
        configureCinematicAndStabilization(for: input)
        configureAudioInput()
    }

    /// Starting the camera and adding the microphone take turns on this queue. Starting in the
    /// middle of the microphone step crashed the app at launch (seen 2026-11-15).
    private static let sessionSetupQueue = DispatchQueue(label: "sessionSetup", qos: .userInitiated)

    private func configureAudioInput() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard granted, let self = self else {
                print("Mic permission denied")
                return
            }

            Self.sessionSetupQueue.async {
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
        if !isObservingSessionErrors {
            isObservingSessionErrors = true
            NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                                   object: captureSession, queue: nil) { notification in
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
                print("Capture session runtime error: \(error.map { "\($0.code) \($0.localizedDescription) \($0.userInfo)" } ?? "unknown")")
            }
        }
        Self.sessionSetupQueue.async { [weak self] in
            self?.captureSession.startRunning()
            print("Capture session running: \(self?.captureSession.isRunning ?? false)")
        }
    }

    /// Every camera change starts with this (main thread) and ends with endCameraChange
    private func beginCameraChange() {
        cameraChangesRunning += 1
        isSwitchingCamera = true
    }

    private func endCameraChange() {
        cameraChangesRunning = max(0, cameraChangesRunning - 1)
        if cameraChangesRunning == 0 { isSwitchingCamera = false }
    }

    func switchCamera() {
        beginCameraChange()

        Self.sessionSetupQueue.async { [weak self] in
            guard let self = self else { return }

            let newPosition: AVCaptureDevice.Position = (self.currentPosition == .front) ? .back : .front
            guard let newCamera = self.blurCamera(for: newPosition) else {
                DispatchQueue.main.async { self.endCameraChange() }
                print("Failed to get camera for position: \(newPosition)")
                return
            }
            self.forgetLiveLevels()
            let wanted = newPosition == .front ? self.frontFormat : self.backFormat
            self.wantsFourK = wanted.fourK
            self.wantedFrameRate = wanted.frameRate
            // A flipped camera starts on its main lens, with blur
            self.replaceVideoInput(with: newCamera, position: newPosition, allLenses: false,
                                   zoom: nil, clearPreview: true)
        }
    }

    /// Swaps the session's camera. Used by the flip button, and by zoom levels that need
    /// the back camera's other lenses (which land on `zoom` and keep the last picture on
    /// screen during the swap). Call off the main thread with isSwitchingCamera set.
    private func replaceVideoInput(with camera: AVCaptureDevice, position: AVCaptureDevice.Position,
                                   allLenses: Bool, zoom: CGFloat?, clearPreview: Bool) {
        let oldInput = currentVideoInput
        let torchWasOn = oldInput?.device.torchMode == .on

        captureSession.beginConfiguration()

        // Remove only the video input, not audio
        if let oldInput = oldInput {
            // The camera being left must not stay frozen for the next time it is used
            unlockFocusAndBrightness(on: oldInput.device)
            captureSession.removeInput(oldInput)
        }

        var didSwap = false
        do {
            let newInput = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(newInput) {
                captureSession.addInput(newInput)
                currentPosition = position
                updateRecordFlip()
                usesAllLenses = allLenses
                print("Camera in use: \(camera.localizedName)\(allLenses ? " (all lenses, no blur)" : "")")
                configureCinematicAndStabilization(for: newInput, zoom: zoom)
                didSwap = true
            }
        } catch {
            print("Failed to switch camera: \(error.localizedDescription)")
        }
        // Keep the old camera rather than a dead screen
        if !didSwap, let oldInput = oldInput, captureSession.canAddInput(oldInput) {
            captureSession.addInput(oldInput)
            configureCinematicAndStabilization(for: oldInput, zoom: nil)
            print("Camera swap failed; kept \(oldInput.device.localizedName)")
        }

        captureSession.commitConfiguration()
        // Synchronizer not started: it would take over videoOutput's frames, and
        // its depth handler is still a no-op, so nothing would reach the recorder.
        // The new camera may differ in HDR support, which changes the buffer format
        setupPixelBufferPool(for: currentVideoSize)

        // The torch belongs to the camera that just left; carry it over
        if didSwap, torchWasOn, camera.hasTorch {
            do {
                try camera.lockForConfiguration()
                camera.torchMode = .on
                camera.unlockForConfiguration()
            } catch {
                print("Failed to keep the torch on: \(error.localizedDescription)")
            }
        }

        DispatchQueue.main.async {
            if clearPreview { self.filteredPreview = nil }
            self.isBlurOffForZoom = self.usesAllLenses || self.slowMoRunning
            self.endCameraChange()
            // Reset pools for the new camera's resolution and format
            self.recordingStream.resetPools()
            self.previewStream.resetPools()
        }
    }

    func toggleFlash() -> Bool {
        // The camera in the session: the torch of a camera that isn't running does nothing
        guard let device = currentVideoInput?.device ?? AVCaptureDevice.default(for: .video),
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
        // Slo-mo is always 1080p: 120 frames stretched 4x play back at 30 a second
        let quality = slowMoRunning ? "1080p" : quality
        let size = videoSize(for: quality)
        setupPixelBufferPool(for: size)
        videoRecorder.quality = quality
        videoRecorder.frameRate = slowMoRunning ? Self.slowMoSpeed / Self.slowMoFactor : activeFrameRate
        videoRecorder.slowFactor = slowMoRunning ? Self.slowMoFactor : 1
        videoRecorder.isHDR = isHDRActive
        // Sideways when recording starts = a sideways (wide) video, fixed for the whole take
        videoRecorder.turnDegrees = DeviceTilt.shared.angle
        // Settings > Mirror selfies off: the saved selfie is flipped back
        takeUnmirrors = !Self.mirrorSelfies
        updateRecordFlip()
        // With a separate preview, the recording stream runs behind real time
        videoRecorder.usesDelayedStream = usesSeparatePreviewStream
        videoRecorder.captureClock = captureSession.synchronizationClock ?? CMClockGetHostTimeClock()
        videoRecorder.startRecording()
        isRecordingActive = true
    }

    /// The size and speed picked on the camera screen ("4K · 60")
    func setVideoFormat(fourK: Bool, frameRate: Int) {
        guard fourK != wantsFourK || frameRate != wantedFrameRate else { return }
        wantsFourK = fourK
        wantedFrameRate = frameRate
        if !photoModeActive, !slowMoActive { reconfigureCurrentCamera() }
    }

    /// Switches between SDR and 10-bit HLG HDR capture by reselecting the Cinematic format.
    func setHDREnabled(_ enabled: Bool) {
        guard enabled != hdrEnabled else { return }
        hdrEnabled = enabled
        reconfigureCurrentCamera()
    }

    /// Turns the separate low-latency preview stream (and heavy recording stabilization) on or off.
    func setEnhancedStabilizationEnabled(_ enabled: Bool) {
        guard enabled != enhancedStabilizationEnabled else { return }
        enhancedStabilizationEnabled = enabled
        reconfigureCurrentCamera()
    }

    /// Re-applies outputs, Cinematic format, and stabilization to the current camera.
    private func reconfigureCurrentCamera() {
        beginCameraChange()  // Pause frame processing while the session changes
        let zoom = displayZoom  // A settings change keeps the zoom (and so the lens) in use
        let started = Date()

        Self.sessionSetupQueue.async { [weak self] in
            guard let self = self else { return }
            if let input = self.currentVideoInput {
                self.captureSession.beginConfiguration()
                self.configureCinematicAndStabilization(for: input, zoom: zoom)
                self.captureSession.commitConfiguration()
                self.setupPixelBufferPool(for: self.currentVideoSize)
            }

            DispatchQueue.main.async {
                self.recordingStream.resetPools()
                self.previewStream.resetPools()
                self.endCameraChange()
                self.isBlurOffForZoom = self.usesAllLenses || self.slowMoRunning
                if self.isModeSwitching {
                    print("Photo/Video switch took \(Int(Date().timeIntervalSince(started) * 1000)) ms")
                    // Let the first pictures from the new setup arrive before the blur lifts
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.isModeSwitching = false
                    }
                }
            }
        }
    }

    /// Adds or removes the separate preview stream, then sets up Cinematic and
    /// stabilization. Call before the session starts or inside a configuration block.
    private func configureCinematicAndStabilization(for input: AVCaptureDeviceInput, zoom: CGFloat? = nil) {
        // A spot held by a tap does not carry over to another tab or camera
        unlockFocusAndBrightness(on: input.device)
        releaseLens(on: input.device)
        resetBrightnessShift(on: input.device)
        updatePreviewOutput()
        removePhotoBlur()
        // Cinematic can't run alongside a second video output: on iPhone 18 Pro Max the
        // session fails at runtime (-11800 / -16401). So, like the Camera app's Action
        // mode, Enhanced Stabilization trades the bokeh for the smoothest footage.
        configureFormatAndCinematic(on: input, enableCinematic: !usesSeparatePreviewStream && !photoModeActive && !slowMoActive)
        // A Photo format bigger than the live view needs (the one behind 24 MP photos) hands
        // over screen-sized live pictures instead: nothing is recorded from them
        let liveWidth = CMVideoFormatDescriptionGetDimensions(input.device.activeFormat.formatDescription).width
        if photoModeActive, liveWidth > 1920 {
            videoOutput.automaticallyConfiguresOutputBufferDimensions = false
            videoOutput.deliversPreviewSizedOutputBuffers = true
        } else if !videoOutput.automaticallyConfiguresOutputBufferDimensions {
            videoOutput.automaticallyConfiguresOutputBufferDimensions = true
        }
        setUpPhotoBlur(for: input)
        if photoBlurUsesDepth {
            // Live depth stops arriving while the picture is being steadied
            videoOutput.connection(with: .video)?.preferredVideoStabilizationMode = .off
        } else {
            enableStabilization()
        }
        resetZoom(for: input.device, to: zoom)
        print("Zoom range: \(input.device.minAvailableVideoZoomFactor)-\(input.device.maxAvailableVideoZoomFactor) raw, display x\(zoomDisplayMultiplier(for: input.device))")
    }

    /// Takes the Photo tab's blur setup out of the session. Depth can't run beside Cinematic
    /// Video, so this runs before every camera setup; setUpPhotoBlur puts it back if wanted.
    private func removePhotoBlur() {
        photoBlurActive = false
        photoBlurUsesDepth = false
        photoFocusPoint = nil
        if captureSession.outputs.contains(depthOutput) { captureSession.removeOutput(depthOutput) }
        if photoOutput.isPortraitEffectsMatteDeliveryEnabled { photoOutput.isPortraitEffectsMatteDeliveryEnabled = false }
        if photoOutput.isDepthDataDeliveryEnabled { photoOutput.isDepthDataDeliveryEnabled = false }
        portraitBlur.reset()
    }

    /// Turns the Photo tab's background blur on for the camera in use and shows the f-number
    /// slider. Back: needs the depth camera; asks for depth (and the person outline) with every
    /// photo and starts the live depth map. Selfie: nothing to set up in the camera, the blur
    /// follows the person. Call after the format is set.
    private func setUpPhotoBlur(for input: AVCaptureDeviceInput) {
        let device = input.device
        guard photoModeActive, !usesAllLenses else { return }
        if device.position == .back {
            guard !device.activeFormat.supportedDepthDataFormats.isEmpty,
                  photoOutput.isDepthDataDeliverySupported,
                  captureSession.canAddOutput(depthOutput) else { return }
            // Allow the full photo size now: changing it at the shot made the first photo
            // after a tab switch arrive without its depth
            let photoSize = bestPhotoDimensions(for: device)
            // A photo over 12 MP only arrives when it does not ask for depth, so those are
            // blurred from the live depth map instead (see capturePhoto)
            let bigPhoto = photoSize.map { Int($0.width) * Int($0.height) > Self.standardPhotoPixels } ?? false
            if !bigPhoto {
                photoOutput.isDepthDataDeliveryEnabled = true
                if photoOutput.isPortraitEffectsMatteDeliverySupported {
                    photoOutput.isPortraitEffectsMatteDeliveryEnabled = true
                }
            }
            captureSession.addOutput(depthOutput)
            depthOutput.isFilteringEnabled = true
            depthOutput.alwaysDiscardsLateDepthData = true
            depthOutput.setDelegate(self, callbackQueue: depthQueue)
            photoBlurUsesDepth = true
        }
        photoBlurActive = true
        let range = PortraitBlur.apertureRange
        let aperture = min(max(chosenAperture, range.lowerBound), range.upperBound)
        print("Photo blur on: \(device.localizedName), from \(photoBlurUsesDepth ? "depth" : "the person's outline")")
        DispatchQueue.main.async {
            self.apertureRange = PortraitBlur.apertureRange
            self.shownAperture = aperture
            self.simulatedAperture = aperture
        }
    }

    private func updatePreviewOutput() {
        let isInSession = captureSession.outputs.contains(previewOutput)
        // The Photo tab records nothing, so it never needs the second stream
        let enhancedStabilizationEnabled = self.enhancedStabilizationEnabled && !photoModeActive && !slowMoActive
        if enhancedStabilizationEnabled && !isInSession {
            previewOutput.setSampleBufferDelegate(self, queue: previewQueue)
            previewOutput.automaticallyConfiguresOutputBufferDimensions = false
            previewOutput.deliversPreviewSizedOutputBuffers = true
            if captureSession.canAddOutput(previewOutput) {
                captureSession.addOutput(previewOutput)
            } else {
                print("Separate preview stream not supported; using a single stream")
            }
        } else if !enhancedStabilizationEnabled && isInSession {
            captureSession.removeOutput(previewOutput)
        }
        usesSeparatePreviewStream = captureSession.outputs.contains(previewOutput)
    }

    func pauseRecording() {
        isRecordingActive = false
        videoRecorder.pauseRecording()
    }

    func resumeRecording() {
        // The camera may have been flipped while the take was paused
        updateRecordFlip()
        isRecordingActive = true
        videoRecorder.resumeRecording()
    }

    /// Which way recorded frames are flipped so a selfie is saved un-mirrored. The switch and
    /// the phone's tilt are fixed for the take; the camera can change while it is paused, and
    /// only selfie-camera frames are ever flipped.
    private func updateRecordFlip() {
        recordFlip = currentPosition == .front && takeUnmirrors
            ? (abs(videoRecorder.turnDegrees) == 90 ? .upDown : .sideToSide) : .none
    }

    func undoLastSegment() -> Bool {
        return videoRecorder.undoLastSegment()
    }

    func discardAllSegments() {
        isRecordingActive = false
        videoRecorder.discardAllSegments()
    }

    func hasRecordedSegments() -> Bool {
        return videoRecorder.hasSegments()
    }

    func getSegmentCount() -> Int {
        return videoRecorder.getSegmentCount()
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        isRecordingActive = false
        videoRecorder.stopRecording(completion: completion)
    }

    /// The largest still size the camera in use offers, up to about 24 megapixels (what the
    /// Camera app saves by default on 48 MP phones). It is allowed on the photo output here,
    /// at shot time, because the output only accepts sizes of the camera connected to it.
    private func bestPhotoDimensions(for device: AVCaptureDevice) -> CMVideoDimensions? {
        let usable = device.activeFormat.supportedMaxPhotoDimensions.filter {
            Int($0.width) * Int($0.height) <= photoPixelLimit
        }
        guard let best = usable.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) else {
            return nil
        }
        if photoOutput.maxPhotoDimensions.width != best.width || photoOutput.maxPhotoDimensions.height != best.height {
            photoOutput.maxPhotoDimensions = best
        }
        photoOutput.maxPhotoQualityPrioritization = .quality
        return best
    }

    /// Switches the camera between photo setup (full-size stills, no background blur) and
    /// video setup (Cinematic blur).
    func setPhotoMode(_ enabled: Bool, slowMo: Bool = false) {
        let slowMo = slowMo && !enabled
        guard enabled != photoModeActive || slowMo != slowMoActive else { return }
        forgetLiveLevels()
        photoModeActive = enabled
        slowMoActive = slowMo
        if currentVideoInput != nil { isModeSwitching = true }
        guard isSwitchingCamera else {
            applyTabToCamera()
            return
        }
        // Another camera change (a flip, say) is still running: this tab's camera is picked
        // only once that has finished, from where it left things
        Self.sessionSetupQueue.async { [weak self] in
            DispatchQueue.main.async { self?.applyTabToCamera() }
        }
    }

    /// Sets the camera up for the tab now showing (main thread)
    private func applyTabToCamera() {
        // The back camera's blur comes from a different camera in each tab (the Cinematic
        // camera for Video, the depth camera for Photo), and the blur stops at a different zoom
        if currentPosition == .back, let current = currentVideoInput?.device {
            let allLenses = wantsAllLenses(at: displayZoom) ?? usesAllLenses
            if let camera = allLenses ? backAllLensCamera : blurCamera(for: .back),
               camera.uniqueID != current.uniqueID {
                beginCameraChange()
                let zoom = displayZoom
                Self.sessionSetupQueue.async { [weak self] in
                    guard let self = self else { return }
                    self.replaceVideoInput(with: camera, position: .back, allLenses: allLenses,
                                           zoom: zoom, clearPreview: false)
                    // Let the first pictures from the new camera arrive before the blur lifts
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.isModeSwitching = false }
                }
                return
            }
        }
        reconfigureCurrentCamera()
    }

    /// Takes a real full-size photo, then applies the same zoom crop, skin smoothing and
    /// filter as the live preview. Hands back nil when no real photo can be taken.
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard !isSwitchingCamera, pendingPhotoCompletion == nil,
              let connection = photoOutput.connection(with: .video),
              let device = (connection.inputPorts.first?.input as? AVCaptureDeviceInput)?.device,
              let dimensions = bestPhotoDimensions(for: device) else {
            // No real photo can be taken right now (the camera is being changed). The small
            // live picture is not saved in its place: the caller is told that no photo came.
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let settings = AVCapturePhotoSettings(format: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        settings.maxPhotoDimensions = dimensions
        settings.photoQualityPrioritization = .quality
        if photoBlurUsesDepth, portraitOn, photoOutput.isDepthDataDeliveryEnabled {
            // The depth map (and person outline) the background blur is drawn from
            settings.isDepthDataDeliveryEnabled = true
            settings.isDepthDataFiltered = true
            settings.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliveryEnabled
        }
        shutterDepth = photoBlurUsesDepth && portraitOn && !settings.isDepthDataDeliveryEnabled
            ? portraitBlur.newestDepth() : nil
        askedPhotoPixels = Int(dimensions.width) * Int(dimensions.height)
        pendingPhotoCompletion = completion
        pendingPhotoID = settings.uniqueID
        // The newest reading from before the press, and only a settled one: while the camera
        // is still finding its brightness (just opened, just flipped, just moved to a new
        // view) a reading is far off, and matching to it gave a much too dark photo
        liveLevelsLock.lock()
        shutterLiveLevels = liveLevels.flatMap { $0.steady && CACurrentMediaTime() - $0.at < 1.2 ? $0.levels : nil }
        photoStartedAt = CACurrentMediaTime()
        liveLevelsLock.unlock()
        shutterLook = ShutterLook(isFront: currentPosition == .front, zoom: digitalZoom,
                                  focusPoint: photoFocusPoint, aperture: chosenAperture,
                                  filter: filterEngine.selectedFilter, filterIntensity: filterEngine.intensity,
                                  mist: mistAmount)
        photoOutput.capturePhoto(with: settings, delegate: self)
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

    private func applyRetouchToPixelBuffer(_ inputBuffer: CVPixelBuffer, stream: FrameStream) -> CVPixelBuffer? {
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

        // HDR frames are smoothed at 16-bit float so the HLG range survives; MetalPetal's
        // own 10-bit YUV input path converts to 8-bit internally and would clip it.
        let isHDRFrame = isHDRActive && isTenBit(inputBuffer)
        guard let mtiContext = isHDRFrame ? makeHDRMTIContext() : mtiContext else {
            return nil
        }

        let mtiImage: MTIImage
        if isHDRFrame {
            guard let halfFloatBuffer = convertToHLGHalfFloat(inputBuffer, stream: stream) else { return nil }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: CVPixelBufferGetWidth(halfFloatBuffer),
                height: CVPixelBufferGetHeight(halfFloatBuffer),
                mipmapped: false)
            descriptor.usage = .shaderRead
            mtiImage = MTIImage(cvPixelBuffer: halfFloatBuffer, planeIndex: 0, textureDescriptor: descriptor, alphaType: .alphaIsOne)
        } else {
            // Create MTIImage directly from CVPixelBuffer (no CIImage conversion!)
            mtiImage = MTIImage(cvPixelBuffer: inputBuffer, alphaType: .alphaIsOne)
        }

        // Apply high-pass skin smoothing filter
        let smoothingFilter = MTIHighPassSkinSmoothingFilter()
        smoothingFilter.inputImage = mtiImage
        smoothingFilter.amount = retouchAmount
        // The radius is in pixels: a 4K frame needs twice the 1080p radius for the same look
        smoothingFilter.radius = retouchRadius * max(1, Float(CVPixelBufferGetWidth(inputBuffer)) / 1920)

        guard let smoothedMTI = smoothingFilter.outputImage else {
            return nil
        }

        // Render to pixel buffer
        do {
            let width = Int(smoothedMTI.size.width)
            let height = Int(smoothedMTI.size.height)

            // Create/reuse pixel buffer pool for retouch output
            if stream.retouchPool == nil {
                let poolAttrs: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: isHDRFrame ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ]
                CVPixelBufferPoolCreate(nil, nil, poolAttrs as CFDictionary, &stream.retouchPool)
            }

            var outputPixelBuffer: CVPixelBuffer?
            if let pool = stream.retouchPool {
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

    private func isTenBit(_ buffer: CVPixelBuffer) -> Bool {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        return format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            || format == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
    }

    /// MetalPetal context whose intermediate textures are 16-bit float (default is 8-bit).
    private func makeHDRMTIContext() -> MTIContext? {
        if let hdrMTIContext = hdrMTIContext { return hdrMTIContext }
        guard let metalDevice = MTLCreateSystemDefaultDevice() else { return nil }
        let options = MTIContextOptions()
        options.workingPixelFormat = .rgba16Float
        do {
            hdrMTIContext = try MTIContext(device: metalDevice, options: options)
            print("MetalPetal HDR context initialized")
        } catch {
            print("Failed to create HDR MTIContext: \(error)")
        }
        return hdrMTIContext
    }

    /// Converts a 10-bit HLG camera frame into HLG-encoded 16-bit float RGBA, a format
    /// MetalPetal can read without losing precision. Core Image handles the
    /// BT.2020 YCbCr-to-RGB conversion from the frame's color attachments.
    private func convertToHLGHalfFloat(_ buffer: CVPixelBuffer, stream: FrameStream) -> CVPixelBuffer? {
        guard let hlgColorSpace = hlgColorSpace else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        if stream.hdrConversionPool == nil {
            let poolAttrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_64RGBAHalf,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            CVPixelBufferPoolCreate(nil, nil, poolAttrs as CFDictionary, &stream.hdrConversionPool)
        }

        var output: CVPixelBuffer?
        if let pool = stream.hdrConversionPool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output)
        }
        guard let output = output else { return nil }
        ciContext.render(CIImage(cvPixelBuffer: buffer), to: output,
                         bounds: CGRect(x: 0, y: 0, width: width, height: height),
                         colorSpace: hlgColorSpace)
        return output
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
            // The active mode is only known once frames flow; log it once per camera setup
            if !hasLoggedStabilization {
                hasLoggedStabilization = true
                print("Stabilization active (\(usesSeparatePreviewStream ? "recording" : "video")): \(stabilizationName(connection.activeVideoStabilizationMode))")
            }
            if usesSeparatePreviewStream {
                // Recording-only stream: skip the work unless the recorder needs frames
                guard videoRecorder.wantsFrames else { return }
                processVideoFrame(sampleBuffer, stream: recordingStream, display: false, record: true)
            } else {
                processVideoFrame(sampleBuffer, stream: recordingStream, display: true, record: true)
            }
        } else if output == previewOutput {
            if !hasLoggedPreviewStabilization {
                hasLoggedPreviewStabilization = true
                let dimensions = CMSampleBufferGetImageBuffer(sampleBuffer).map { "\(CVPixelBufferGetWidth($0))x\(CVPixelBufferGetHeight($0))" } ?? "?"
                print("Stabilization active (preview): \(stabilizationName(connection.activeVideoStabilizationMode)), \(dimensions)")
            }
            processVideoFrame(sampleBuffer, stream: previewStream, display: true, record: false)
        } else if output == audioOutput {
            if !hasLoggedAudio {
                print("Audio samples received")
                hasLoggedAudio = true
            }
            videoRecorder.writeAudioBuffer(sampleBuffer)
        }
    }

    /// Retouch + filters on one frame, then display it and/or write it to the recorder.
    /// Digital zoom crop, skin brightness/warmth and the chosen filter: the look shared by
    /// the live preview, recorded video and photos.
    private func applyZoomSkinAndFilter(_ input: CIImage, scaleZoomBack: Bool = true,
                                        look: ShutterLook? = nil) -> CIImage {
        var ciImage = input
        // Digital zoom: crop the centre and scale it back up to the full frame
        let cropZoom = look?.zoom ?? digitalZoom
        if cropZoom > 1.01 {
            let extent = ciImage.extent
            let crop = CGRect(x: extent.midX - extent.width / (2 * cropZoom),
                              y: extent.midY - extent.height / (2 * cropZoom),
                              width: extent.width / cropZoom,
                              height: extent.height / cropZoom).integral
            if scaleZoomBack {
                ciImage = ciImage.cropped(to: crop)
                    .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                    .transformed(by: CGAffineTransform(scaleX: extent.width / crop.width,
                                                       y: extent.height / crop.height))
                    .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
                    .cropped(to: extent)
            } else {
                // Photos keep the cropped pixels as they are: no pointless upscaling
                ciImage = ciImage.cropped(to: crop)
                    .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            }
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

        if let look = look {
            // A photo: the filter and mist as they were at the shutter press
            return applyMist(to: filterEngine.applyFilter(look.filter, intensity: look.filterIntensity, to: ciImage),
                             amount: look.mist)
        }
        return applyMist(to: filterEngine.applyFilter(to: ciImage))
    }

    /// The Mist slider: the look of a mist (diffusion) filter on the lens. Bright areas spill
    /// a soft glow over their surroundings and the darks lift a touch; detail stays sharp
    /// because the glow is laid over the picture, the picture itself is never blurred.
    /// Sizes follow the picture's width, so video frames and big photos look the same.
    private func applyMist(to image: CIImage, amount: Float? = nil) -> CIImage {
        let strength = Double(amount ?? mistAmount) * Self.mistFullStrength
        let extent = image.extent
        // Slow motion has a third of the time per frame: the glow is left out there
        guard strength > 0.005, !slowMoRunning, !extent.isInfinite, extent.width > 0 else { return image }
        func scaled(_ input: CIImage, by gain: Double, bias: Double = 0) -> CIImage {
            input.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)])
        }
        let white = CIVector(x: 1, y: 1, z: 1, w: 1)
        // The glow is worked out on a quarter-size copy of the picture (a sixteenth of the
        // work). It is soft all over, so nothing is lost; the smooth shrink keeps small
        // lights from flickering from frame to frame.
        let small = image.applyingFilter("CILanczosScaleTransform",
                                         parameters: [kCIInputScaleKey: 0.25, kCIInputAspectRatioKey: 1])
        // Only what is brighter than the threshold glows
        let threshold = 0.42
        let gain = 1 / (1 - threshold)
        let bright = scaled(small, by: gain, bias: -threshold * gain)
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputMaxComponents": white])
            .clampedToExtent()
        // `share` = the glow's reach as a share of the picture's width
        func glow(_ share: Double) -> CIImage {
            bright.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: extent.width * share / 4])
                .transformed(by: CGAffineTransform(scaleX: 4, y: 4))
                .cropped(to: extent)
        }
        // Laying a glow over anything brighter than white (HDR video) would dim it, so the
        // glows go over a copy held at white, and the original wins wherever it is brighter
        let capped = image.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: -8, y: -8, z: -8, w: 0),
            "inputMaxComponents": white])
        // A tight glow, then a wide one
        var output = scaled(glow(0.012), by: 0.55 * strength)
            .applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: capped])
        output = scaled(glow(0.05), by: 0.75 * strength)
            .applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: output])
        let lift = 0.012 * strength
        return scaled(output, by: 1 - lift, bias: lift)
            .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: extent)
    }

    /// The Photo tab's blur on a live frame as it arrives from the camera (still sideways).
    private func livePortraitBlur(_ frame: CIImage, pixelBuffer: CVPixelBuffer) -> CIImage {
        guard photoBlurUsesDepth else {
            return portraitBlur.livePreview(frame, personIn: pixelBuffer, aperture: chosenAperture)
        }
        // The display is the camera frame turned 90 degrees clockwise: undo that to find the
        // focus spot in the frame (same mapping as setCinematicFocus on the back camera)
        let shown = photoFocusPoint ?? CGPoint(x: 0.5, y: 0.5)
        return portraitBlur.livePreview(frame, focusAt: CGPoint(x: shown.y, y: 1 - shown.x), aperture: chosenAperture)
    }

    private func processVideoFrame(_ sampleBuffer: CMSampleBuffer, stream: FrameStream, display wantsDisplay: Bool, record: Bool) {
        guard !isSwitchingCamera else { return }
        var display = wantsDisplay
        if slowMoRunning {
            // The screen needs 30 pictures a second, not 120: three frames in four skip the
            // live picture, and are skipped altogether when nothing is being recorded
            slowFrameCount &+= 1
            if slowFrameCount % Self.slowMoFactor != 0 {
                guard isRecordingActive else { return }
                display = false
            }
        }
        guard var pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Photo tab: note how bright the live picture is, three times a second
        if photoModeActive {
            let now = CACurrentMediaTime()
            liveLevelsLock.lock()
            let takingPhoto = photoStartedAt.map { now - $0 < 3 } ?? false
            let measureLive = !takingPhoto && now - (liveLevels?.at ?? 0) >= 0.3
            liveLevelsLock.unlock()
            // A black reading is a hiccup, not the scene: the last good one stays
            if measureLive, let levels = brightnessLevels(of: CIImage(cvPixelBuffer: pixelBuffer)),
               case let mean = levels.reduce(0, +) / Float(max(levels.count, 1)), mean > 0.01 {
                liveLevelsLock.lock()
                // Settled = about as bright as the reading just before it
                var steady = false
                if let last = liveLevels, now - last.at < 0.8 {
                    let lastMean = last.levels.reduce(0, +) / Float(max(last.levels.count, 1))
                    steady = abs(mean - lastMean) <= 0.08 * max(mean, lastMean)
                }
                liveLevels = (levels, CACurrentMediaTime(), steady)
                liveLevelsLock.unlock()
            }
        }

        // Apply retouch (skin smoothing) directly to pixel buffer if enabled
        var isRetouchedHDR = false
        if retouchEnabled {
            if let smoothedBuffer = applyRetouchToPixelBuffer(pixelBuffer, stream: stream) {
                pixelBuffer = smoothedBuffer
                isRetouchedHDR = CVPixelBufferGetPixelFormatType(smoothedBuffer) == kCVPixelFormatType_64RGBAHalf
            }
        }

        // Retouched HDR frames are HLG-encoded floats with no color tags, so say so;
        // camera frames carry their own color attachments
        var ciImage: CIImage
        if isRetouchedHDR, let hlgColorSpace = hlgColorSpace {
            ciImage = CIImage(cvPixelBuffer: pixelBuffer, options: [.colorSpace: hlgColorSpace])
        } else {
            ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        }
        if photoBlurActive, portraitOn, display {
            ciImage = livePortraitBlur(ciImage, pixelBuffer: pixelBuffer)
        }
        ciImage = ciImage.oriented(.right)

        // Mirror front camera horizontally for selfie mode (like native camera/TikTok)
        if currentPosition == .front {
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                .translatedBy(x: -ciImage.extent.width, y: 0))
        }

        let filteredImage = applyZoomSkinAndFilter(ciImage)

        if !hasLoggedFilter && filterEngine.selectedFilter != nil {
            print("Filter rendering: \(filterEngine.selectedFilter!.name)")
            hasLoggedFilter = true
        }

        // Scale to video size and write to recorder
        let scaleX = currentVideoSize.width / filteredImage.extent.width
        let scaleY = currentVideoSize.height / filteredImage.extent.height
        let scaledImage = filteredImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(origin: .zero, size: currentVideoSize))

        // Only while a recording is running: drawing every idle frame at video size was wasted work
        if record, videoRecorder.wantsFrames, let pool = pixelBufferPool {
            // The saved frame only; the live picture always stays like a mirror
            var scaledImage = scaledImage
            if recordFlip == .sideToSide {
                scaledImage = scaledImage.transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                    .translatedBy(x: -currentVideoSize.width, y: 0))
            } else if recordFlip == .upDown {
                scaledImage = scaledImage.transformed(by: CGAffineTransform(scaleX: 1, y: -1)
                    .translatedBy(x: 0, y: -currentVideoSize.height))
            }
            var outputPixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputPixelBuffer)

            if let outputBuffer = outputPixelBuffer {
                // Render with explicit bounds to avoid memory issues
                // HDR recording buffers are 10-bit YUV tagged BT.2020/HLG; encode to match
                let outputColorSpace = (isHDRActive ? hlgColorSpace : nil) ?? CGColorSpaceCreateDeviceRGB()
                ciContext.render(scaledImage, to: outputBuffer, bounds: CGRect(origin: .zero, size: currentVideoSize), colorSpace: outputColorSpace)
                videoRecorder.writePixelBuffer(outputBuffer, at: timestamp)
            }
        }

        // Convert to UIImage for display
        guard display else { return }
        // A 4K frame is far more than the screen can show: the live picture gets a 1080-wide copy
        var shown = filteredImage
        if shown.extent.width > 2000 {
            let shrink = 1080 / shown.extent.width
            shown = shown.transformed(by: CGAffineTransform(scaleX: shrink, y: shrink))
        }
        guard let cgImage = ciContext.createCGImage(shown, from: shown.extent.integral) else { return }
        let uiImage = UIImage(cgImage: cgImage)

        DispatchQueue.main.async { [weak self] in
            self?.filteredPreview = uiImage
        }
    }
}

extension CameraManager: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData,
                         timestamp: CMTime, connection: AVCaptureConnection) {
        portraitBlur.store(depthData)
    }
}

extension CameraManager: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        // Depth data available for bokeh (disabled for now)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error { print("Photo capture error: \(error.localizedDescription)") }
        photoQueue.async { [weak self] in
            guard let self = self else { return }
            let image = error == nil ? self.makeFinishedPhoto(from: photo, look: self.shutterLook) : nil
            self.shutterDepth = nil
            // Asked for a big photo at the blur camera and got the standard size: this iPhone
            // does not hand big ones over this way
            let got = photo.resolvedSettings.photoDimensions
            let refused = error == nil && self.photoBlurUsesDepth
                && self.askedPhotoPixels > Self.standardPhotoPixels
                && Int(got.width) * Int(got.height) <= Self.standardPhotoPixels
            DispatchQueue.main.async {
                let completion = self.pendingPhotoCompletion
                self.pendingPhotoCompletion = nil
                self.pendingPhotoID = nil
                // A photo that failed is reported as such: the small live picture is never
                // saved in its place
                completion?(image)
                if refused, !self.bigPhotosRefused {
                    print("Big photos refused by this camera; back to 12 MP with the photo's own depth")
                    self.bigPhotosRefused = true
                    self.reconfigureCurrentCamera()
                }
            }
        }
    }

    /// Always the last call for a shot. If its photo never came (the camera was changed in
    /// the middle of it), the shutter must not be left waiting for it.
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        let shot = resolvedSettings.uniqueID
        // Through the photo queue, so a photo that did come is handed over first
        photoQueue.async { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.pendingPhotoID == shot,
                      let completion = self.pendingPhotoCompletion else { return }
                print("Photo never arrived\(error.map { ": \($0.localizedDescription)" } ?? "")")
                self.pendingPhotoCompletion = nil
                self.pendingPhotoID = nil
                self.shutterDepth = nil
                completion(nil)
            }
        }
    }

    /// Runs the full-size still through the same look as the preview.
    private func makeFinishedPhoto(from photo: AVCapturePhoto, look: ShutterLook?) -> UIImage? {
        let aperture = look?.aperture ?? chosenAperture
        guard var pixelBuffer = photo.pixelBuffer else { return nil }
        print("Photo captured: \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))")
        if retouchEnabled, let smoothed = retouchPhotoBuffer(pixelBuffer) {
            pixelBuffer = smoothed
        }
        // Photos carry their own orientation tag (video frames are always sideways)
        let rawOrientation = (photo.metadata[kCGImagePropertyOrientation as String] as? UInt32) ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
        var ciImage = matchedToScreen(CIImage(cvPixelBuffer: pixelBuffer)).oriented(orientation)
        if !portraitOn {
            // Portrait is off: the photo stays as it was taken
        } else if photoBlurUsesDepth {
            // Focus where the live picture does: the tapped spot, else the middle
            let focus = (look.map { $0.focusPoint } ?? photoFocusPoint) ?? CGPoint(x: 0.5, y: 0.5)
            if let blurred = portraitBlur.finishedPhoto(ciImage, photo: photo, orientation: orientation,
                                                        aperture: aperture, focusAt: focus, context: ciContext) {
                ciImage = blurred
            } else if let liveDepth = shutterDepth,
                      let blurred = portraitBlur.finishedPhoto(ciImage, liveDepth: liveDepth, orientation: orientation,
                                                               aperture: aperture, focusAt: focus, context: ciContext) {
                ciImage = blurred
            } else {
                print("Photo blur skipped: no depth for the shot")
            }
        } else if photoBlurActive {
            ciImage = portraitBlur.finishedPhoto(ciImage, aperture: aperture)
        }
        if look?.isFront ?? (currentPosition == .front) {
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                .translatedBy(x: -ciImage.extent.width, y: 0))
        }
        let finished = applyZoomSkinAndFilter(ciImage, scaleZoomBack: false, look: look)
        guard let cgImage = ciContext.createCGImage(finished, from: finished.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// A reading of one camera or view says nothing about the next one
    private func forgetLiveLevels() {
        liveLevelsLock.lock()
        liveLevels = nil
        shutterLiveLevels = nil
        liveLevelsLock.unlock()
    }

    /// How light each part of a picture is, as a small grid of values from 0 (black) to 1
    /// (white) the way a screen shows them, for comparing two pictures of the same view.
    private func brightnessLevels(of image: CIImage) -> [Float]? {
        let longSide = max(image.extent.width, image.extent.height)
        guard longSide > 0, let screenSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let small = image.applyingFilter("CILanczosScaleTransform",
                                         parameters: [kCIInputScaleKey: 48 / longSide, kCIInputAspectRatioKey: 1.0])
        // Inside the edge, where the shrunken picture fades out
        let bounds = small.extent.insetBy(dx: 2, dy: 2).integral
        let width = Int(bounds.width), height = Int(bounds.height)
        guard width > 0, height > 0 else { return nil }
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes {
            ciContext.render(small, toBitmap: $0.baseAddress!, rowBytes: width * 16, bounds: bounds,
                             format: .RGBAf, colorSpace: screenSpace)
        }
        return stride(from: 0, to: pixels.count, by: 4).map {
            min(max(0.2126 * pixels[$0] + 0.7152 * pixels[$0 + 1] + 0.0722 * pixels[$0 + 2], 0), 1)
        }
    }

    /// The curve that turns the photo's spread of dark and light into the live picture's, as
    /// 64 steps from black to white. Nil when the two already agree.
    private func toneCurve(from still: [Float], to live: [Float]) -> [Float]? {
        let stillSorted = still.sorted(), liveSorted = live.sorted()
        func level(_ sorted: [Float], _ share: Float) -> Float {
            sorted[min(sorted.count - 1, Int(share * Float(sorted.count - 1) + 0.5))]
        }
        // 0.75 stops either way at most, as a screen shows it: enough for the gap between
        // the live picture and a still, too little to spoil a photo if a reading is off
        let limit = powf(2, 0.75 / 2.2)
        // Black stays black and white stays white; in between, the darkest tenth of the photo
        // becomes as light as the darkest tenth of the live picture, and so on up
        var points: [(x: Float, y: Float)] = [(0, 0)]
        for share: Float in [0.02, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.98] {
            let x = level(stillSorted, share)
            guard x - points[points.count - 1].x >= 0.02, x <= 0.98 else { continue }
            let y = min(max(level(liveSorted, share), x / limit), min(x * limit, 1))
            points.append((x, max(y, points[points.count - 1].y)))
        }
        points.append((1, 1))

        let steps = 64
        var curve = [Float](repeating: 0, count: steps)
        var segment = 0
        for index in 0..<steps {
            let x = Float(index) / Float(steps - 1)
            while segment < points.count - 2, x > points[segment + 1].x { segment += 1 }
            let from = points[segment], to = points[segment + 1]
            curve[index] = from.y + (to.y - from.y) * (x - from.x) / (to.x - from.x)
        }
        // No step much steeper or flatter than the photo's own, so nothing bands or goes flat
        let even = 1 / Float(steps - 1)
        var rises = (1..<steps).map { min(max(curve[$0] - curve[$0 - 1], even / 3), even * 3) }
        let total = rises.reduce(0, +)
        if total < 1 { rises = rises.map { $0 / total } }
        for index in 1..<steps { curve[index] = min(curve[index - 1] + rises[index - 1], 1) }
        // Round off the corners
        for _ in 0..<2 {
            let before = curve
            for index in 1..<(steps - 1) {
                curve[index] = (before[index - 1] + 2 * before[index] + before[index + 1]) / 4
            }
        }
        let change = (0..<steps).map { abs(curve[$0] - Float($0) * even) }.max() ?? 0
        return change >= 0.01 ? curve : nil
    }

    /// The iPhone develops a still differently from its live picture (deeper shadows, other
    /// brightness), so a photo came out darker or lighter than what was on screen. This gives
    /// the still the live picture's dark-to-light spread, as read just before the shutter
    /// press. At most 0.75 stops either way; with no fresh live reading the photo is left alone.
    private func matchedToScreen(_ photo: CIImage) -> CIImage {
        liveLevelsLock.lock()
        let live = shutterLiveLevels
        shutterLiveLevels = nil
        photoStartedAt = nil
        liveLevelsLock.unlock()
        guard let live, !live.isEmpty,
              let still = brightnessLevels(of: photo), !still.isEmpty,
              let curve = toneCurve(from: still, to: live),
              let screenSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return photo }
        let table = curve.flatMap { [$0, $0, $0] }
        return photo.applyingFilter("CIColorCurves", parameters: [
            "inputCurvesData": table.withUnsafeBufferPointer { Data(buffer: $0) },
            "inputCurvesDomain": CIVector(x: 0, y: 1),
            "inputColorSpace": screenSpace,
        ])
    }

    /// Skin smoothing for a full-size still. The blur radius is in pixels, so it grows with the
    /// photo to give the same look as on the 1920-pixel-wide video frames.
    private func retouchPhotoBuffer(_ input: CVPixelBuffer) -> CVPixelBuffer? {
        guard cachedFaceBounds != nil else { return nil }
        mtiLock.lock()
        defer { mtiLock.unlock() }
        guard let mtiContext = mtiContext else { return nil }

        let width = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)
        let smoothingFilter = MTIHighPassSkinSmoothingFilter()
        smoothingFilter.inputImage = MTIImage(cvPixelBuffer: input, alphaType: .alphaIsOne)
        smoothingFilter.amount = retouchAmount
        smoothingFilter.radius = retouchRadius * Float(max(width, height)) / 1920
        guard let output = smoothingFilter.outputImage else { return nil }

        var outputBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &outputBuffer)
        guard let buffer = outputBuffer else { return nil }
        do {
            try mtiContext.render(output, to: buffer)
            return buffer
        } catch {
            print("MetalPetal photo render error: \(error)")
            return nil
        }
    }
}

enum RetouchPreset {
    case natural    // Subtle, barely noticeable
    case soft       // Balanced, everyday use
    case glam       // Strong smoothing with glow
    case porcelain  // Maximum smoothing, pale/flawless look
}

/// A person, pet or thing the camera has found in the live picture
struct SubjectBox: Identifiable, Equatable {
    let id: Int
    /// Where it is in the displayed picture (portrait, 0...1, origin top-left)
    let rect: CGRect
    /// The one Cinematic focus is holding on to
    let isFocused: Bool
}

extension CameraManager: AVCaptureMetadataOutputObjectsDelegate {
    /// Runs on the main queue. Turns what the camera tracks into one box per subject:
    /// around the face when it can be seen, like the iPhone Camera.
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard #available(iOS 26.0, *) else { return }
        if photoModeActive {
            showFaces(objects.compactMap { $0 as? AVMetadataFaceObject })
            return
        }
        // A face, head and body of one person share a group; ungrouped things stand alone
        var groups: [Int: [AVMetadataObject]] = [:]
        for object in objects {
            let key = object.groupID >= 0 ? object.groupID : -2 - object.objectID
            groups[key, default: []].append(object)
        }
        // Only the face in focus gets a box (yellow). Other people, bodies and objects get
        // none: the user found white boxes and long body rectangles confusing.
        var faces: [Int: CGRect] = [:]
        var faceIDs: [Int: Int] = [:]
        var focusedSubject: Int?
        for (key, members) in groups {
            guard let face = members.first(where: { $0.type == .face })
                    ?? members.first(where: { $0.type.rawValue.lowercased().contains("head") })
            else { continue }
            faces[key] = displayRect(forDeviceRect: face.bounds)
            faceIDs[key] = face.objectID
            if members.contains(where: { $0.cinematicVideoFocusMode != .none }) {
                focusedSubject = min(focusedSubject ?? key, key)
            }
        }
        latestFaces = faces
        latestFaceIDs = faceIDs
        facesSeenAt = CACurrentMediaTime()

        // The box shows for a moment whenever focus moves to another face, and on a tap
        let now = CACurrentMediaTime()
        if focusedSubject != lastFocusedSubject {
            boxesShownSince = now
        }
        lastFocusedSubject = focusedSubject
        var shown: Set<Int> = []
        if let focusedSubject, now - boxesShownSince < Self.boxesStayFor { shown.insert(focusedSubject) }
        if let tappedFace, now < tappedFaceUntil { shown.insert(tappedFace) }
        let boxes = shown.sorted().compactMap { id in
            faces[id].map { SubjectBox(id: id, rect: $0, isFocused: true) }
        }
        if boxes != subjectBoxes { subjectBoxes = boxes }
    }

    /// Photo tab: a yellow box on each face for two seconds after it is found, like the
    /// iPhone Camera. None while a tap is holding the focus somewhere.
    private func showFaces(_ faces: [AVMetadataFaceObject]) {
        let now = CACurrentMediaTime()
        var seen: [Int: CFTimeInterval] = [:]
        var rects: [Int: CGRect] = [:]
        var boxes: [SubjectBox] = []
        for face in faces {
            let first = faceFirstSeen[face.faceID] ?? now
            seen[face.faceID] = first
            let rect = displayRect(forDeviceRect: face.bounds)
            rects[face.faceID] = rect
            let tapped = face.faceID == tappedFace && now < tappedFaceUntil
            if tapped || (!lensHeldByTap && now - first < 2) {
                boxes.append(SubjectBox(id: face.faceID, rect: rect, isFocused: true))
            }
        }
        faceFirstSeen = seen
        latestFaces = rects
        latestFaceIDs = [:]
        boxes.sort { $0.id < $1.id }
        if boxes != subjectBoxes { subjectBoxes = boxes }
    }

    /// The camera reports boxes in the sensor's own sideways picture. The display is that
    /// picture turned 90 degrees clockwise, mirrored on the selfie camera, and shows only
    /// the centre when zoomed digitally: the exact reverse of setCinematicFocus's mapping.
    private func displayRect(forDeviceRect device: CGRect) -> CGRect {
        let upright = currentPosition == .front
            ? CGRect(x: device.minY, y: device.minX, width: device.height, height: device.width)
            : CGRect(x: 1 - device.maxY, y: device.minX, width: device.height, height: device.width)
        // The Photo tab's blur view is cropped in a little further (1 everywhere else)
        let zoom = digitalZoom
        return CGRect(x: 0.5 + (upright.minX - 0.5) * zoom, y: 0.5 + (upright.minY - 0.5) * zoom,
                      width: upright.width * zoom, height: upright.height * zoom)
    }
}
