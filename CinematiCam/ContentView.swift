//
//  ContentView.swift
//  CinematiCam
//
//  Created by Abhishek Dangol on 1/25/26.
//

import SwiftUI
import Photos
import UIKit
import MediaPlayer
import AVFoundation
import AVKit
import AudioToolbox
import Combine

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let permissionsManager = PermissionsManager()
    @StateObject private var cameraManager = CameraManager()
    @State private var showPermissionDeniedAlert = false
    @State private var isBackCamera = false
    @State private var isFlashOn = false
    @State private var blurIntensity: Double = 0.5 // 0 = f/8 (min blur), 1 = f/1.4 (max blur)
    @State private var isRecording = false
    @State private var isRecordingPaused = false
    @State private var hasRecordedSegments = false
    @State private var recordingSeconds = 0
    @State private var recordingTimer: Timer?
    @State private var recordingDotOpacity = 1.0
    @State private var showSavedToast = false
    @ObservedObject private var tilt = DeviceTilt.shared
    @State private var savedToastHide: DispatchWorkItem?
    @State private var showSaveFailedAlert = false
    /// A finished clip that could not be saved to Photos, kept so the save can be retried
    @State private var unsavedVideoURL: URL?
    /// A photo that could not be saved to Photos, kept so the save can be retried
    @State private var unsavedPhoto: UIImage?
    @State private var showPhotoNotSavedAlert = false
    /// A photo or video that could not be made at all: the words for the message
    @State private var captureProblem: String?
    /// Recordings the app closed on last time, before they reached Photos
    @State private var interruptedTakes: [VideoRecorder.InterruptedTake] = []
    @State private var showInterruptedAlert = false
    @State private var lookedForInterrupted = false
    @State private var showSettings = false
    @AppStorage("selectedFilter") private var selectedFilterName = "Natural"
    // Each camera remembers its own size and speed: back starts at 4K 30, selfie at HD 30
    @AppStorage("videoQualityBack") private var backVideoQuality = "4K"
    @AppStorage("videoFrameRateBack") private var backVideoFrameRate = 30
    @AppStorage("videoQualityFront") private var frontVideoQuality = "1080p"
    @AppStorage("videoFrameRateFront") private var frontVideoFrameRate = 30
    /// The size of the camera in use
    private var videoQuality: String {
        get { cameraManager.isFrontCamera ? frontVideoQuality : backVideoQuality }
        nonmutating set {
            if cameraManager.isFrontCamera { frontVideoQuality = newValue } else { backVideoQuality = newValue }
        }
    }
    /// The speed of the camera in use
    private var videoFrameRate: Int {
        get { cameraManager.isFrontCamera ? frontVideoFrameRate : backVideoFrameRate }
        nonmutating set {
            if cameraManager.isFrontCamera { frontVideoFrameRate = newValue } else { backVideoFrameRate = newValue }
        }
    }
    @AppStorage("showGrid") private var showGrid = false
    @AppStorage("showLevel") private var showLevel = false
    /// Settings timer: seconds counted down after the shutter press (0 = off)
    @AppStorage("timerSeconds") private var timerSeconds = 0
    @AppStorage("hdrVideo") private var hdrVideo = false
    /// On = selfies are saved as the screen shows them; off = as other people see you
    @AppStorage("mirrorSelfies") private var mirrorSelfies = true
    @AppStorage("enhancedStabilization") private var enhancedStabilization = false
    @State private var filterIntensity: Double = 0.8
    @State private var showRetouchControls = false
    @State private var isPhotoMode = false
    /// The SLO-MO tab: a kind of Video (only counts while the Photo tab is not showing)
    @State private var isSlowMo = false
    private var slowTab: Bool { isSlowMo && !isPhotoMode }
    /// Selfie Photo only: true shows (and saves) the whole picture the camera takes, which
    /// has more at the sides than the normal view. This is the selfie "zoom out".
    /// Settings > Photo shape: "4:3" (the whole camera picture), "1:1" or "16:9" (tall)
    @AppStorage("photoShape") private var photoShape = "4:3"
    /// The shape (width / height) the Photo tab shows and saves; nil = the whole picture.
    /// 4:3 is the whole camera picture on both cameras, like the iPhone Camera.
    private var photoCropAspect: CGFloat? {
        guard isPhotoMode else { return nil }
        switch photoShape {
        case "1:1": return 1
        case "16:9": return 9.0 / 16.0
        default: return nil
        }
    }
    /// A photo trimmed to a shape (width / height): the centre of the picture. nil = all of it
    private static func trimmed(_ image: UIImage, toShape aspect: CGFloat?) -> UIImage {
        guard let aspect = aspect else { return image }
        return centreCrop(image, to: CGSize(width: aspect, height: 1))
    }
    /// Finished photos are trimmed, turned and flipped here, one at a time, off the screen's thread
    private static let photoFinishing = DispatchQueue(label: "com.abhishekdangol.CinematiCam.photoFinishing",
                                                      qos: .userInitiated)
    @State private var previewSize: CGSize = .zero
    @State private var capturedPhoto: UIImage?
    @State private var showPhotoPreview = false

    @State private var showFilters = false
    @StateObject private var lookTiles = LookTileRenderer()
    @State private var showBlurSlider = false
    @State private var focusIndicatorID = 0
    /// Where a tap that was not on a face landed: it gets the yellow square (nil = hidden)
    @State private var tapSquarePoint: CGPoint?
    /// Where the brightness sun sits after a tap (nil = hidden)
    @State private var sunAnchor: CGPoint?
    /// The brightness a drag started from (nil = no drag under way)
    @State private var dragStartShift: Float?
    /// Press and hold: where the finger now on the picture went down, the timer that turns
    /// it into a lock, and whether it already did (its lift must not count as a tap)
    @State private var holdTouchStart: CGPoint?
    @State private var holdTimer: DispatchWorkItem?
    @State private var holdFiredThisTouch = false
    @GestureState private var fingerOnPicture = false
    @State private var pinchStartZoom: CGFloat?

    // Teleprompter
    @State private var teleprompterText: String = ""
    @State private var showTeleprompterSheet = false
    @State private var teleprompterEnabled = false
    @State private var teleprompterScrollSpeed: Double = 1.0
    @State private var teleprompterScrollOffset: CGFloat = 0
    @State private var teleprompterTimer: Timer? = nil

    // Photo capture animation
    @State private var thumbnailPhoto: UIImage?
    @State private var thumbnailVideo: UIImage?
    /// Photos' own id for the photo / the clip last saved, so the thumbnail can open the
    /// Photos app on that item.
    @State private var lastSavedPhotoID: String?
    @State private var lastSavedVideoID: String?
    /// The clip the video thumbnail stands for, so tapping the thumbnail can play it.
    @State private var lastVideoURL: URL?
    /// Shows the photo or clip just taken (opened by the thumbnail beside the shutter).
    @State private var showLastCapture = false
    /// True from End until the new clip's thumbnail has grown into place
    @State private var justSavedVideo = false
    @State private var showCaptureFlash = false
    @State private var captureAnimationPhase: CaptureAnimationPhase = .idle
    /// Shutter presses so far, and the last press whose real photo has arrived. While they
    /// differ, the thumbnail is the picture the screen showed at the press, standing in for
    /// the real photo (a 24 MP one takes about 2 s).
    @State private var photoShot = 0
    @State private var photoLandedShot = 0

    // Video Preview & Edit
    @State private var showVideoPreview = false
    @State private var showVideoEditor = false

    // Captions
    @State private var showCaptionOptions = false
    @State private var recordedVideoURL: URL?
    @State private var showCaptionEditor = false
    @State private var captions: [CaptionSegment] = []
    @State private var isTranscribing = false
    @State private var isProcessingVideo = false
    private let speechManager = SpeechRecognitionManager()
    private let captionRenderer = CaptionRenderer()
    private let videoProcessor = VideoProcessor()

    // Inline retouch controls
    @State private var selectedRetouchParam = 1 // default to Smooth selected
    @State private var retouchAmount: Float = 0.6
    /// The wand panel's Mist slider: glow around bright areas, 0 = off
    @State private var mistAmount: Float = 0
    @State private var retouchRadius: Float = 10.0
    @State private var savedRetouchAmount: Float = 0.6
    @State private var savedRetouchRadius: Float = 10.0
    @State private var showUndoAlert = false
    @State private var showDiscardAlert = false
    @State private var showSwitchToPhotoAlert = false
    @State private var countdownValue: Int = 0
    @State private var countdownScale: CGFloat = 1.0
    /// Goes up when a countdown starts or is cancelled, so an old one stops ticking
    @State private var countdownID = 0
    @StateObject private var volumeHandler = VolumeButtonHandler()
    private let filters = FilterLibrary.all
    var body: some View {
        ZStack {
            // Raw camera preview (fallback)
            CameraPreviewView(session: cameraManager.captureSession)
                .ignoresSafeArea()

            // Filtered preview overlay (tap to move Cinematic focus)
            GeometryReader { geometry in
                FilteredPreviewView(image: cameraManager.filteredPreview, fillsScreen: false,
                                    cropAspect: photoCropAspect,
                                    blurred: cameraManager.isModeSwitching)
                    .onAppear { previewSize = geometry.size }
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        handleFocusTap(at: location, viewSize: geometry.size)
                    }
                    // Pinch to zoom, starting from the zoom the pinch began at
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                let startZoom = pinchStartZoom ?? cameraManager.displayZoom
                                pinchStartZoom = startZoom
                                cameraManager.setDisplayZoom(startZoom * scale)
                            }
                            .onEnded { _ in pinchStartZoom = nil }
                    )
                    .simultaneousGesture(brightnessDrag)
                    .simultaneousGesture(holdToLock(viewSize: geometry.size))
                    .overlay {
                        focusOverlay(viewSize: geometry.size)
                    }
            }
            .ignoresSafeArea()

            // Shows when the phone is held almost straight
            if showLevel {
                LevelLine()
            }

            // Rule of thirds grid
            if showGrid {
                ThirdsGrid(aspect: photoCropAspect)
            }
        }
        // Teleprompter overlay
        .overlay {
            if teleprompterEnabled && !teleprompterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TeleprompterOverlayView(
                    text: teleprompterText,
                    scrollOffset: $teleprompterScrollOffset,
                    onDismiss: {
                        teleprompterEnabled = false
                        resetTeleprompterScroll()
                    }
                )
            }
        }
        // Top: quick controls like the Camera app's top row; recording time below them
        .overlay(alignment: .top) {
            VStack(spacing: 10) {
                if !isRecording {
                    topBar
                }
                if isRecording || isRecordingPaused {
                    recordingStatusRow
                }
                if cameraManager.focusLocked {
                    lockPill
                }
            }
            .padding(.top, 8)
        }
        .overlay { sidewaysTimePill }
        // Bottom, laid out like the Camera app: zoom buttons, shutter row, mode switch
        .overlay(alignment: .bottom) {
            VStack(spacing: 14) {
                // Retouch controls (when enabled and controls visible)
                if showRetouchControls && !isRecording {
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            ForEach(0..<4) { index in
                                let paramIcons = ["face.dashed", "wand.and.rays", "circle.hexagongrid", "cloud.fog"]
                                let paramNames = ["Natural", "Smooth", "Radius", "Mist"]
                                Button {
                                    HapticFeedback.impact()
                                    selectedRetouchParam = index
                                    if index == 0 {
                                        // Natural: save current values, then zero out
                                        if retouchAmount > 0 || retouchRadius > 1 {
                                            savedRetouchAmount = retouchAmount
                                            savedRetouchRadius = retouchRadius
                                        }
                                        retouchAmount = 0
                                        retouchRadius = 0
                                        updateCameraRetouchParams()
                                    } else if index != 3, retouchAmount == 0 && retouchRadius == 0 {
                                        // Coming from Natural: restore saved values
                                        retouchAmount = savedRetouchAmount
                                        retouchRadius = savedRetouchRadius
                                        updateCameraRetouchParams()
                                    }
                                } label: {
                                    VStack(spacing: 2) {
                                        Image(systemName: paramIcons[index])
                                            .font(.system(size: 14))
                                        Text(paramNames[index])
                                            .font(.system(size: 9))
                                    }
                                    .foregroundColor(selectedRetouchParam == index ? .yellow : .white.opacity(0.7))
                                    .frame(width: 60, height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedRetouchParam == index ? Color.yellow.opacity(0.15) : Color.black.opacity(0.2))
                                    )
                                }
                            }
                        }

                        if selectedRetouchParam != 0 {
                            HStack {
                                Text(currentParamName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 55, alignment: .leading)
                                Slider(value: currentParamBinding, in: currentParamRange)
                                    .tint(.yellow)
                                    .disabled(mistOffHere)
                                    .onChange(of: retouchAmount) { _ in updateCameraRetouchParams() }
                                    .onChange(of: retouchRadius) { _ in updateCameraRetouchParams() }
                                Text(currentParamValueText)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.yellow)
                                    .frame(width: 45, alignment: .trailing)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.horizontal, 8)
                    .transition(.opacity)
                }

                // Cinematic depth (f-stop) slider: lower f-number = stronger background blur
                if showFocusSlider, let apertureRange = cameraManager.apertureRange, !isRecording {
                    HStack {
                        Image(systemName: "f.cursive")
                            .foregroundColor(.white.opacity(0.7))
                        Slider(value: $cameraManager.simulatedAperture, in: apertureRange)
                            .tint(.yellow)
                            .onChange(of: cameraManager.simulatedAperture) { newValue in
                                cameraManager.setSimulatedAperture(newValue)
                            }
                        Text(String(format: "f/%.1f", cameraManager.simulatedAperture))
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 44)
                    }
                    .padding(.horizontal, 24)
                }

                if showFilters && !isRecording {
                    filterPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    zoomRow
                    shutterRow
                    modeStrip
                }
            }
            .padding(.bottom, showFilters && !isRecording ? 0 : 8)
        }
        // Looks tiles show the live camera picture, made only while the panel is open
        .onChange(of: showFilters) { open in
            cameraManager.wantsLookTiles = open
            if !open { lookTiles.clear() }
        }
        .onReceive(cameraManager.$lookTileSource) { source in
            guard showFilters, let source else { return }
            lookTiles.update(source: source, filters: filters)
        }
        .onChange(of: isPhotoMode) { photoTab in
            // Photo tab: full-size photos (no background blur). Video tab: Cinematic blur.
            cameraManager.setPhotoMode(photoTab, slowMo: isSlowMo)
        }
        .onAppear {
            FilterLibrary.prepareInBackground()
            lookForInterruptedRecording()
            permissionsManager.requestCameraPermission { granted in
                if granted {
                    cameraManager.setPhotoMode(isPhotoMode)
                    cameraManager.hdrEnabled = hdrVideo
                    shareVideoFormats()
                    cameraManager.wantsFourK = videoQuality == "4K"
                    cameraManager.wantedFrameRate = videoFrameRate
                    cameraManager.enhancedStabilizationEnabled = enhancedStabilization
                    cameraManager.configure()
                    cameraManager.startSession()
                    // Restore saved filter or default to Natural
                    let savedFilter = filters.first { $0.name == selectedFilterName } ?? filters[0]
                    cameraManager.setFilter(savedFilter)
                    cameraManager.setFilterIntensity(filterIntensity)
                    // Apply default skin smoothing
                    cameraManager.setRetouch(true)
                    updateCameraRetouchParams()
                    // Third first-launch question, right after the microphone one (the welcome page
                    // promises camera, microphone and Photos), instead of at the first save.
                    // Asking for the microphone again only waits for that answer; it shows no second popup.
                    AVCaptureDevice.requestAccess(for: .audio) { _ in
                        DispatchQueue.main.async {
                            permissionsManager.requestPhotoLibraryPermission { _ in }
                        }
                    }
                } else {
                    showPermissionDeniedAlert = true
                }
            }
        }
        .alert("Camera Access Required", isPresented: $showPermissionDeniedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Camera access is required. Please enable in Settings.")
        }
        .alert("Delete Last Clip?", isPresented: $showUndoAlert) {
            Button("Delete", role: .destructive) {
                let segmentCountBefore = cameraManager.getSegmentCount()
                if cameraManager.undoLastSegment() {
                    recordingSeconds = max(0, recordingSeconds - 3)
                    if segmentCountBefore <= 1 {
                        hasRecordedSegments = false
                        isRecordingPaused = false
                        recordingSeconds = 0
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete the last recorded clip?")
        }
        .alert("Video Not Saved", isPresented: $showSaveFailedAlert) {
            Button("Try Again") {
                if let url = unsavedVideoURL { saveFinishedVideo(url) }
            }
            Button("Discard Video", role: .destructive) {
                if let url = unsavedVideoURL { VideoRecorder.removeUnsaved(url) }
                unsavedVideoURL = nil
                thumbnailVideo = nil
            }
        } message: {
            Text("CinematiCam could not save this video to Photos. Allow Photos access for CinematiCam in Settings, then tap Try Again.")
        }
        .alert("Discard All Clips?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                recordingTimer?.invalidate()
                recordingTimer = nil
                cameraManager.discardAllSegments()
                isRecording = false
                isRecordingPaused = false
                hasRecordedSegments = false
                recordingSeconds = 0
                resetTeleprompterScroll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to discard all recorded clips? This cannot be undone.")
        }
        .alert("Unsaved Recording", isPresented: $showSwitchToPhotoAlert) {
            Button("Save & Switch", role: .none) {
                cameraManager.stopRecording { url in
                    if let url = url {
                        generateVideoThumbnail(from: url)
                        saveToPhotoLibrary(url: url)
                    }
                }
                isRecordingPaused = false
                hasRecordedSegments = false
                recordingSeconds = 0
                resetTeleprompterScroll()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPhotoMode = true
                }
            }
            Button("Discard & Switch", role: .destructive) {
                recordingTimer?.invalidate()
                recordingTimer = nil
                cameraManager.discardAllSegments()
                isRecordingPaused = false
                hasRecordedSegments = false
                recordingSeconds = 0
                resetTeleprompterScroll()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPhotoMode = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have an unsaved recording. Would you like to save or discard it before switching to Photo mode?")
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                List {
                    Section {
                        Picker("Timer", selection: $timerSeconds) {
                            Text("Off").tag(0)
                            Text("3s").tag(3)
                            Text("10s").tag(10)
                        }
                    } footer: {
                        Text("Counts down after you press the shutter, then takes the photo or starts the video. Press the shutter again to cancel.")
                    }
                    Section {
                        Picker("Quality", selection: Binding(get: { videoQuality }, set: { videoQuality = $0 })) {
                            Text("4K").tag("4K")
                            Text("1080p").tag("1080p")
                            Text("720p").tag("720p")
                        }
                        .onChange(of: videoQuality) { _ in applyVideoFormat() }
                        .disabled(isRecordingPaused)
                        // The selfie camera with blur stops at 30
                        Picker("Speed", selection: Binding(get: { cameraManager.sixtyAvailable ? videoFrameRate : 30 },
                                                           set: { videoFrameRate = $0 })) {
                            Text("30").tag(30)
                            Text("60").tag(60)
                        }
                        .onChange(of: videoFrameRate) { _ in applyVideoFormat() }
                        .disabled(isRecordingPaused || !cameraManager.sixtyAvailable)
                        // Locked while paused: clips in different formats can't be joined
                        Toggle("HDR Video", isOn: $hdrVideo)
                            .onChange(of: hdrVideo) { enabled in
                                cameraManager.setHDREnabled(enabled)
                            }
                            .disabled(isRecordingPaused)
                        Toggle("Enhanced Stabilization", isOn: $enhancedStabilization)
                            .onChange(of: enhancedStabilization) { enabled in
                                cameraManager.setEnhancedStabilizationEnabled(enabled)
                            }
                            .disabled(isRecordingPaused)
                    } header: {
                        Text(cameraManager.isFrontCamera ? "Video (selfie camera)" : "Video (back camera)")
                    } footer: {
                        Text("Enhanced Stabilization gives the smoothest footage, like Action mode, but turns off the Cinematic background blur.")
                    }
                    Section {
                        Picker("Photo shape", selection: $photoShape) {
                            Text("4:3").tag("4:3")
                            Text("Square").tag("1:1")
                            Text("16:9").tag("16:9")
                        }
                    } header: {
                        Text("Photo")
                    } footer: {
                        Text("4:3 is the normal photo shape. 16:9 is tall and fills the screen.")
                    }
                    Section {
                        Toggle("Mirror selfies", isOn: $mirrorSelfies)
                    } footer: {
                        Text("On: a selfie is saved the way you see it on screen. Off: it is saved the way other people see you, so writing reads the right way.")
                    }
                    Section("Guides") {
                        Toggle("Rule of Thirds Grid", isOn: $showGrid)
                        Toggle("Level", isOn: $showLevel)
                    }
                    if Diagnostics.isOn {
                        Section {
                            NavigationLink("Diagnostics") { DiagnosticsView() }
                        } footer: {
                            Text("A log of what the app did, for our own testing. It is taken out before the app is released.")
                        }
                    }
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showTeleprompterSheet) {
            TeleprompterInputView(
                scriptText: $teleprompterText,
                scrollSpeed: $teleprompterScrollSpeed,
                isEnabled: $teleprompterEnabled
            )
        }
        // Add Captions overlay after saving
        .overlay {
            if showCaptionOptions {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            showCaptionOptions = false
                            transcribeAndShowEditor()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "captions.bubble")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Add Captions")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(25)
                        }

                        Button {
                            showCaptionOptions = false
                            recordedVideoURL = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .padding(.bottom, 120)
                }
            }
        }
        .sheet(isPresented: $showCaptionEditor) {
            if let url = recordedVideoURL {
                CaptionEditorView(
                    videoURL: url,
                    captions: $captions,
                    onExport: {
                        exportWithCaptions()
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showLastCapture) {
            LastCaptureView(photo: isPhotoMode ? thumbnailPhoto : nil,
                            videoURL: isPhotoMode ? nil : lastVideoURL,
                            savedAssetID: { isPhotoMode ? lastSavedPhotoID : lastSavedVideoID })
        }
        .fullScreenCover(isPresented: $showVideoPreview) {
            if let url = recordedVideoURL {
                VideoPreviewView(
                    videoURL: url,
                    onDiscard: {
                        // Delete temp file and return to camera
                        try? FileManager.default.removeItem(at: url)
                        recordedVideoURL = nil
                        showVideoPreview = false
                    },
                    onEdit: {
                        // Open video editor - delay to let preview dismiss first
                        showVideoPreview = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showVideoEditor = true
                        }
                    },
                    onSave: {
                        // Save video as-is
                        saveToPhotoLibrary(url: url)
                        showVideoPreview = false
                        recordedVideoURL = nil
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showVideoEditor) {
            if let url = recordedVideoURL {
                VideoEditorView(
                    videoURL: url,
                    onCancel: {
                        // Return to preview
                        showVideoEditor = false
                        showVideoPreview = true
                    },
                    onExport: { splitPoints, deletedSegments, trimStart, trimEnd, volume in
                        showVideoEditor = false
                        isProcessingVideo = true

                        videoProcessor.exportWithSegments(
                            sourceURL: url,
                            splitPoints: splitPoints,
                            deletedSegments: deletedSegments,
                            trimStart: trimStart,
                            trimEnd: trimEnd,
                            volume: volume
                        ) { outputURL, error in
                            isProcessingVideo = false
                            if let outputURL = outputURL {
                                saveToPhotoLibrary(url: outputURL)
                            } else {
                                print("Export failed: \(error?.localizedDescription ?? "unknown")")
                            }
                            recordedVideoURL = nil
                        }
                    }
                )
            }
        }
        .overlay {
            if isTranscribing {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Transcribing...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                }
            }
        }
        .overlay {
            if isProcessingVideo {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Exporting...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                }
            }
        }
        // Capture flash effect
        .overlay {
            if showCaptureFlash {
                Color.white
                    .ignoresSafeArea()
            }
        }
        // Capture animation (full screen to thumbnail)
        .overlay {
            if captureAnimationPhase != .idle, let photo = capturedPhoto {
                GeometryReader { geometry in
                    Image(uiImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: captureAnimationPhase == .fullScreen ? geometry.size.width : 70,
                            height: captureAnimationPhase == .fullScreen ? geometry.size.height : 70
                        )
                        .clipShape(RoundedRectangle(cornerRadius: captureAnimationPhase == .fullScreen ? 0 : 10))
                        .position(
                            x: captureAnimationPhase == .fullScreen ? geometry.size.width / 2 : 65,
                            y: captureAnimationPhase == .fullScreen ? geometry.size.height / 2 : geometry.size.height - 85
                        )
                }
                .ignoresSafeArea()
            }
        }
        // Countdown overlay
        .overlay {
            if countdownValue > 0 {
                // The picture stays clear behind the number, so the pose can be checked
                Text("\(countdownValue)")
                    .font(.system(size: 170, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.55), radius: 14)
                    .scaleEffect(countdownScale)
                    .turnsWithPhone()
                    .allowsHitTesting(false)
            }
        }
        // Video saved toast (keep for videos only)
        .overlay(alignment: .center) {
            if showSavedToast {
                SavedMessage()
                    .transition(.opacity.combined(with: .offset(y: 12)))
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                if isRecording {
                    // Pause recording when going to background (TikTok style)
                    cameraManager.pauseRecording()
                    recordingTimer?.invalidate()
                    recordingTimer = nil
                    isRecording = false
                    isRecordingPaused = true
                    hasRecordedSegments = true
                    print("Recording paused due to background")
                }
            } else if newPhase == .active {
                cameraManager.startSession()
                print("Camera resumed")
            }
        }
        .onChange(of: volumeHandler.volumeButtonPressed) { _ in
            handleVolumeButtonPress()
        }
        .modifier(CameraButtonModifier { handleVolumeButtonPress() })
        // Closing the player hands audio back to the camera, which shifts the volume
        // reading a moment later; treat that as the new baseline, not a press
        .onChange(of: showVideoPreview) { _ in
            volumeHandler.suppressPresses(for: 2.0)
        }
        .onChange(of: showVideoEditor) { _ in
            volumeHandler.suppressPresses(for: 2.0)
        }
        .onChange(of: isRecording) { recording in
            if recording {
                startTeleprompterScroll()
            } else {
                stopTeleprompterScroll()
            }
        }
    }

    // MARK: - Camera-app style controls

    private func glassButton(_ icon: String, size: CGFloat = 40, isActive: Bool = false, name: String? = nil,
                             action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.impact()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundColor(isActive ? .yellow : .white)
                    .frame(width: size, height: size)
                    .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
                    .turnsWithPhone()
                // The button's name, small, under it (top bar only)
                if let name {
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }

    /// Opens one tool panel (Portrait slider, Touch Up or Filters) and closes the others;
    /// tapping the open one closes it.
    private func showPanel(blur: Bool = false, retouch: Bool = false, filters: Bool = false) {
        withAnimation(.easeInOut(duration: 0.2)) {
            showBlurSlider = blur && !showBlurSlider
            showRetouchControls = retouch && !showRetouchControls
            showFilters = filters && !showFilters
        }
    }

    /// The camera in use can blur the background (or could, at another zoom level)
    private var blurAvailable: Bool {
        cameraManager.apertureRange != nil || cameraManager.isBlurOffForZoom
    }

    /// The blur strength slider: shown and hidden by the Portrait button
    private var showFocusSlider: Bool {
        showBlurSlider && !cameraManager.isBlurOffForZoom
    }

    /// Portrait: shows or hides the blur strength slider, in Photo and Video. The blur
    /// itself is always on. Dimmed while a zoom level has moved to a lens that has no blur.
    private var portraitButton: some View {
        glassButton("person.and.background.dotted", isActive: showFocusSlider, name: "Blur") {
            showPanel(blur: true)
        }
        .opacity(cameraManager.isBlurOffForZoom ? 0.35 : 1)
        .disabled(cameraManager.isBlurOffForZoom)
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            // Flash exists only on the back camera
            if isBackCamera {
                glassButton(isFlashOn ? "bolt.fill" : "bolt.slash.fill", isActive: isFlashOn, name: "Flash") {
                    isFlashOn = cameraManager.toggleFlash()
                }
                Spacer()
            }
            if blurAvailable {
                portraitButton
                Spacer()
            }
            glassButton("text.justify.leading", isActive: teleprompterEnabled, name: "Script") {
                showTeleprompterSheet = true
            }
            Spacer()
            glassButton("wand.and.stars", isActive: showRetouchControls, name: "Touch up") { showPanel(retouch: true) }
            Spacer()
            glassButton("camera.filters", isActive: showFilters, name: "Looks") { showPanel(filters: true) }
            Spacer()
            glassButton("gearshape.fill", name: "Settings") { showSettings = true }
        }
        .padding(.horizontal, 20)
        .opacity(countdownValue > 0 ? 0 : 1)
    }

    /// Recording time (red while recording, like the Camera app). While paused it is
    /// flanked by Discard all (left) and Delete last clip (right).
    private var isHeldSideways: Bool { abs(tilt.angle) == 90 }

    private var timePill: some View {
        HStack(spacing: 5) {
            if isRecordingPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 11))
            }
            Text(formatTime(recordingSeconds))
                .font(.system(size: 17, design: .monospaced))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(isRecordingPaused ? Color.black.opacity(0.6) : Color.red))
        .fixedSize()
        .turnsWithPhone()
    }

    /// Phone held sideways during a recording: the time sits in the middle of the long
    /// edge that is at the bottom for the person holding it.
    @ViewBuilder private var sidewaysTimePill: some View {
        if isHeldSideways && (isRecording || isRecordingPaused) {
            timePill
                .frame(width: 30, height: 90)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: tilt.angle == 90 ? .leading : .trailing)
                .allowsHitTesting(false)
        }
    }

    private var recordingStatusRow: some View {
        ZStack {
            // Held sideways, the time moves to the bottom edge (see sidewaysTimePill)
            if !isHeldSideways {
                timePill
            }

            if isRecordingPaused && hasRecordedSegments {
                HStack {
                    glassButton("xmark") { showDiscardAlert = true }
                    Spacer()
                    glassButton("arrow.uturn.backward") { showUndoAlert = true }
                }
            }
        }
        .frame(height: 40)
        .padding(.horizontal, 20)
    }

    /// ".5", "1", "2.5": zoom numbers the way the Camera app writes them
    private func zoomLabel(_ value: CGFloat) -> String {
        let text = String(format: "%.1f", value)
        if text.hasSuffix(".0") { return String(text.dropLast(2)) }
        return text.hasPrefix("0.") ? String(text.dropFirst()) : text
    }

    /// Zoom buttons above the shutter. The one in use is yellow and shows the live zoom.
    /// Filter picker in the bottom third of the screen, like TikTok's effects tray:
    /// strength slider on top, then a grid of filters, four per row, that scrolls up and down.
    private var filterPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundColor(.white.opacity(0.7))
                Slider(value: $filterIntensity, in: 0...1)
                    .tint(.yellow)
                    .disabled(selectedFilterName == "Natural")
                    .onChange(of: filterIntensity) { newValue in
                        cameraManager.setFilterIntensity(newValue)
                    }
                Text("\(Int(filterIntensity * 100))%")
                    .foregroundColor(.white)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 40)
                Button {
                    HapticFeedback.impact()
                    withAnimation(.easeInOut(duration: 0.25)) { showFilters = false }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }
            }
            .opacity(selectedFilterName == "Natural" ? 0.4 : 1)
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                          spacing: 14) {
                    ForEach(0..<filters.count, id: \.self) { index in
                        Button {
                            HapticFeedback.impact()
                            selectedFilterName = filters[index].name
                            cameraManager.setFilter(filters[index])
                            cameraManager.setFilterIntensity(filterIntensity)
                        } label: {
                            FilterThumbnailView(
                                filter: filters[index],
                                isSelected: selectedFilterName == filters[index].name,
                                liveImage: lookTiles.images[filters[index].name]
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .frame(height: UIScreen.main.bounds.height * 0.36)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(Color.black.opacity(0.88))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private var zoomRow: some View {
        if !cameraManager.isFrontCamera {
            zoomPresetRow
        } else {
            // The selfie camera already shows its whole picture: nothing to zoom out to
            Color.clear.frame(height: 40)
        }
    }

    private var zoomPresetRow: some View {
        let presets = cameraManager.zoomPresets
        let zoom = cameraManager.displayZoom
        let active = presets.last(where: { $0 <= zoom + 0.01 }) ?? presets.first
        return HStack(spacing: 10) {
            ForEach(presets, id: \.self) { preset in
                let isActive = preset == active
                Button {
                    HapticFeedback.impact()
                    cameraManager.setDisplayZoom(preset, animated: true)
                } label: {
                    Text(isActive ? zoomLabel(zoom) + "×" : zoomLabel(preset))
                        .font(.system(size: isActive ? 13 : 12, weight: .semibold))
                        .foregroundColor(isActive ? .yellow : .white)
                        .frame(width: isActive ? 40 : 32, height: isActive ? 40 : 32)
                        .background(Color.black.opacity(0.45), in: Circle())
                        .turnsWithPhone()
                }
            }
        }
        .frame(height: 40)
    }

    private func roundThumbnail(_ image: UIImage, popIn: Bool = false) -> some View {
        Button {
            // The stand-in thumbnail does not open: it is a screen-sized copy, and sharing
            // it would send that instead of the real photo
            if isPhotoMode, photoLandedShot != photoShot { return }
            showLastCapture = true
        } label: {
            SavedThumbnail(image: image, popIn: popIn) { justSavedVideo = false }
        }
    }

    /// Left of the shutter: last photo/clip when idle; Pause while recording; Resume while paused
    @ViewBuilder private var leftOfShutter: some View {
        if isPhotoMode {
            if let thumbnail = thumbnailPhoto, captureAnimationPhase == .idle {
                roundThumbnail(thumbnail)
            }
        } else if isRecording {
            // Pause is the one thing the Camera app lacks, so it is a solid white button
            // with its name under it
            LabeledRecordingButton(title: "Pause", action: pauseRecordingNow) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.black)
            }
        } else if isRecordingPaused {
            // Resume: same white button, with a play triangle
            LabeledRecordingButton(title: "Resume", action: resumeRecordingNow) {
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.black)
                    .offset(x: 2) // a triangle looks off-centre unless nudged right
            }
        } else if let thumbnail = thumbnailVideo {
            // Right after End, the new clip's picture grows into place (the "saved" sign)
            roundThumbnail(thumbnail, popIn: justSavedVideo)
        }
    }

    /// White ring. Photo: white dot. Video: red dot to start; once a recording is going
    /// the centre becomes the blinking REC sign and End (right of it) stops and saves.
    @ViewBuilder private var shutterButton: some View {
        if !isPhotoMode && (isRecording || isRecordingPaused) {
            RecordingIndicator(isPaused: isRecordingPaused)
        } else {
            startButton
        }
    }

    /// Right of the shutter during a recording: End stops and saves the video.
    private var endRecordingButton: some View {
        LabeledRecordingButton(title: "End", action: finishRecording) {
            Image(systemName: "xmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)
        }
    }

    private var startButton: some View {
        Button {
            shootOrCountDown()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 74, height: 74)
                if isPhotoMode {
                    Circle().fill(Color.white).frame(width: 62, height: 62)
                } else {
                    Circle().fill(Color.red).frame(width: 62, height: 62)
                }
            }
            .frame(width: 80, height: 80)
        }
    }

    /// The shutter (button or volume key) with nothing recording: shoots now, or counts
    /// down first when the Settings timer is on. A press during the count cancels it.
    private func shootOrCountDown() {
        if countdownValue > 0 {
            countdownID += 1
            countdownValue = 0
            HapticFeedback.impact()
            return
        }
        guard timerSeconds > 0 else {
            shootNow()
            return
        }
        countdownID += 1
        countdownValue = timerSeconds
        HapticFeedback.impact()
        animateCountdownNumber()
        tickCountdown(id: countdownID, inPhoto: isPhotoMode)
    }

    private func tickCountdown(id: Int, inPhoto: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard id == countdownID, countdownValue > 0 else { return }
            // Switching between Photo and Video in the middle calls it off
            guard inPhoto == isPhotoMode else {
                countdownValue = 0
                return
            }
            countdownValue -= 1
            if countdownValue == 0 {
                shootNow()
            } else {
                HapticFeedback.impact()
                animateCountdownNumber()
                tickCountdown(id: id, inPhoto: inPhoto)
            }
        }
    }

    private func shootNow() {
        if isPhotoMode {
            takePhoto()
        } else {
            HapticFeedback.impact()
            startRecordingNow()
        }
    }

    private var shutterRow: some View {
        HStack(spacing: 0) {
            // Clear fillers keep both sides the same width even when a side is empty,
            // so the shutter stays centred
            Color.clear
                .frame(maxWidth: .infinity)
                .overlay { leftOfShutter }
            shutterButton
            // Right of the shutter: End during a recording; flip camera otherwise. While
            // paused both show: End stays in its place and flip moves to the far edge.
            Color.clear
                .frame(maxWidth: .infinity)
                .overlay {
                    if !isPhotoMode && (isRecording || isRecordingPaused) { endRecordingButton }
                }
                .overlay(alignment: isRecordingPaused && !isPhotoMode ? .trailing : .center) {
                    if !isRecording {
                        glassButton("arrow.triangle.2.circlepath", size: isRecordingPaused && !isPhotoMode ? 40 : 48) {
                            // Cinematic reconfiguration can take a moment; cover it generously
                            volumeHandler.suppressPresses(for: 3.0)
                            cameraManager.switchCamera()
                            isBackCamera.toggle()
                        }
                    }
                }
        }
        .frame(height: 80)
        .padding(.horizontal, 12)
    }

    private func modeButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.impact()
            action()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(isSelected ? .yellow : .white)
                .frame(width: 76, height: 30)
                .background(Capsule().fill(isSelected ? Color.white.opacity(0.18) : Color.clear))
        }
    }

    /// SLO-MO or VIDEO. A paused recording stays in the tab it started in: slowed and
    /// ordinary clips can't be joined into one video.
    private func chooseVideoTab(slow: Bool) {
        if isRecordingPaused, slow != isSlowMo { return }
        if slow != slowTab, countdownValue > 0 {
            countdownID += 1
            countdownValue = 0
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            isSlowMo = slow
            isPhotoMode = false
        }
        cameraManager.setPhotoMode(false, slowMo: slow)
    }

    /// SLO-MO / VIDEO / PHOTO under the shutter. Hidden (but keeping its space, so the
    /// shutter stays put) while a clip is being recorded.
    private var modeStrip: some View {
        HStack(spacing: 4) {
            modeButton("SLO-MO", isSelected: slowTab) {
                chooseVideoTab(slow: true)
            }
            .opacity(isRecordingPaused && !slowTab ? 0.4 : 1)
            modeButton("VIDEO", isSelected: !isPhotoMode && !isSlowMo) {
                chooseVideoTab(slow: false)
            }
            .opacity(isRecordingPaused && slowTab ? 0.4 : 1)
            modeButton("PHOTO", isSelected: isPhotoMode) {
                if isRecordingPaused && hasRecordedSegments {
                    showSwitchToPhotoAlert = true
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { isPhotoMode = true }
                }
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .opacity(isRecording ? 0 : 1)
        .allowsHitTesting(!isRecording)
    }

    private func pauseRecordingNow() {
        cameraManager.pauseRecording()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        isRecordingPaused = true
        hasRecordedSegments = true
    }

    private func resumeRecordingNow() {
        cameraManager.resumeRecording()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            recordingSeconds += 1
        }
        isRecording = true
        isRecordingPaused = false
    }

    /// Ends the recording (all clips joined into one video) and saves it straight to
    /// Photos, like the iPhone Camera app: no preview screen in between.
    private func finishRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        cameraManager.stopRecording { url in
            DispatchQueue.main.async {
                guard let url = url else {
                    captureProblem = "The video could not be finished, so nothing was saved."
                    return
                }
                justSavedVideo = true
                generateVideoThumbnail(from: url)
                lastVideoURL = url
                saveFinishedVideo(url)
            }
        }
        isRecording = false
        isRecordingPaused = false
        hasRecordedSegments = false
        recordingSeconds = 0
        resetTeleprompterScroll()
    }

    private func handleVolumeButtonPress() {
        // Only the camera screen reacts to volume buttons. Video playback in the
        // preview/editor shifts the system volume, which must not start a recording.
        guard !showVideoPreview, !showVideoEditor, !showCaptionEditor, !showLastCapture,
              !showSettings, !showTeleprompterSheet, !isProcessingVideo, !isTranscribing else { return }
        HapticFeedback.impact()

        if isPhotoMode {
            shootOrCountDown()
        } else {
            // Toggle video recording (pause/resume)
            if isRecording {
                // Pause recording
                cameraManager.pauseRecording()
                recordingTimer?.invalidate()
                recordingTimer = nil
                isRecording = false
                isRecordingPaused = true
                hasRecordedSegments = true
            } else if isRecordingPaused {
                // Resume recording
                cameraManager.resumeRecording()
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    recordingSeconds += 1
                }
                isRecording = true
                isRecordingPaused = false
            } else {
                shootOrCountDown()
            }
        }
    }

    /// The boxes the camera draws around what it is tracking (yellow = in focus, sized to
    /// the face like the iPhone Camera), plus the square a tap leaves behind.
    @ViewBuilder
    private func focusOverlay(viewSize: CGSize) -> some View {
        ZStack {
            ForEach(cameraManager.subjectBoxes) { box in
                if let frame = previewFrame(for: box.rect, viewSize: viewSize) {
                    RoundedRectangle(cornerRadius: min(frame.width, frame.height) * 0.12)
                        .stroke(box.isFocused ? Color.yellow : Color.white.opacity(0.75),
                                lineWidth: box.isFocused ? 1.5 : 1)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .animation(.linear(duration: 0.08), value: frame)
                        .transition(.opacity)
                }
            }
            if let point = tapSquarePoint {
                RoundedRectangle(cornerRadius: Self.tapSquareSide * 0.12)
                    .stroke(Color.yellow, lineWidth: 1.5)
                    .frame(width: Self.tapSquareSide, height: Self.tapSquareSide)
                    .position(point)
                    .transition(.opacity)
            }
            if let anchor = sunAnchor {
                BrightnessSun(shift: cameraManager.brightnessShift,
                              showsTrack: dragStartShift != nil || cameraManager.brightnessShift != 0)
                    .position(anchor)
                    .transition(.opacity)
            }
        }
        // Boxes fade out when the camera takes them away
        .animation(.easeOut(duration: 0.3), value: cameraManager.subjectBoxes.isEmpty)
        // A lock that ends without a tap (another camera or tab) takes its marks with it
        .onChange(of: cameraManager.focusLocked) { locked in
            if !locked { hideFocusMarksLater() }
        }
        .allowsHitTesting(false)
        .alert("Photo Not Saved", isPresented: $showPhotoNotSavedAlert) {
            Button("Try Again") {
                if let photo = unsavedPhoto { savePhotoToLibrary(image: photo) }
            }
            Button("Discard Photo", role: .destructive) {
                unsavedPhoto = nil
                thumbnailPhoto = nil
            }
        } message: {
            Text("CinematiCam could not save this photo to Photos. Allow Photos access for CinematiCam in Settings, then tap Try Again.")
        }
        .alert("Not Saved", isPresented: Binding(get: { captureProblem != nil },
                                                 set: { if !$0 { captureProblem = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(captureProblem ?? "")
        }
        .alert("Recording Interrupted", isPresented: $showInterruptedAlert) {
            Button("Save to Photos") { saveInterruptedRecordings() }
            Button("Discard", role: .destructive) { discardInterruptedRecordings() }
            // iOS adds a third button beside a red one. Named, so it is clear nothing is
            // lost: the recording is kept and offered again the next time the app opens.
            Button("Not Now", role: .cancel) { }
        } message: {
            Text(interruptedMessage)
        }
    }

    /// How the live picture sits in the preview: its drawn size, and how much of it hangs
    /// off each side. Photo mode fills the view (overflow cropped equally); video mode fits
    /// the whole frame (equal bars, so the "crop" is negative). Same math covers both.
    private func previewLayout(viewSize: CGSize) -> (size: CGSize, crop: CGPoint)? {
        guard let imageSize = cameraManager.filteredPreview?.size,
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let widthRatio = viewSize.width / imageSize.width
        let heightRatio = viewSize.height / imageSize.height
        var scale = min(widthRatio, heightRatio)
        if let aspect = photoCropAspect {
            // The photo fills a box of the chosen shape, what hangs over cut off equally
            let box = FilteredPreviewView.box(aspect: aspect, in: viewSize)
            scale = max(box.width / imageSize.width, box.height / imageSize.height)
        }
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return (size, CGPoint(x: (size.width - viewSize.width) / 2, y: (size.height - viewSize.height) / 2))
    }

    /// A box given in the displayed picture (0...1) as points in the preview
    private func previewFrame(for rect: CGRect, viewSize: CGSize) -> CGRect? {
        guard let layout = previewLayout(viewSize: viewSize) else { return nil }
        return CGRect(x: rect.minX * layout.size.width - layout.crop.x,
                      y: rect.minY * layout.size.height - layout.crop.y,
                      width: rect.width * layout.size.width, height: rect.height * layout.size.height)
    }

    /// Converts a tap on the aspect-filled preview to a normalized point in the
    /// displayed image, sends it to Cinematic focus, and shows the focus square.
    private func handleFocusTap(at location: CGPoint, viewSize: CGSize, lock: Bool = false) {
        // Lifting the finger after a press-and-hold is not a tap (it would undo the lock)
        if !lock, holdFiredThisTouch { return }
        guard let layout = previewLayout(viewSize: viewSize) else { return }
        // Square / 16:9 photos: the black bars around the box are not part of the picture
        if let aspect = photoCropAspect,
           !FilteredPreviewView.box(aspect: aspect, in: viewSize).contains(location) { return }
        let normalized = CGPoint(x: (location.x + layout.crop.x) / layout.size.width,
                                 y: (location.y + layout.crop.y) / layout.size.height)
        // Ignore taps on the black bars
        guard (0...1).contains(normalized.x), (0...1).contains(normalized.y) else { return }

        HapticFeedback.impact()
        if lock {
            cameraManager.lockFocusAndBrightness(atDisplayPoint: normalized)
        } else {
            cameraManager.setCinematicFocus(atDisplayPoint: normalized)
        }

        // The brightness sun marks the tap. It is placed once and stays put: beside the
        // tapped subject (whose yellow box is about to show) or else beside the tapped spot,
        // on the right, or on the left at the screen edge.
        // A lock is on the spot, not on a subject that may walk away, so it gets the square
        let subject = lock ? nil : cameraManager.latestSubjectRects
            .compactMap { previewFrame(for: $0, viewSize: viewSize) }
            .first { $0.contains(location) }
        // A tap on anything else (a mug, a plant) gets a yellow square of its own, like the
        // iPhone Camera, so it is clear where the focus went
        let side = Self.tapSquareSide
        tapSquarePoint = subject == nil ? location : nil
        let box = subject ?? CGRect(x: location.x - side / 2, y: location.y - side / 2, width: side, height: side)
        let gap: CGFloat = 18
        let fitsOnRight = box.maxX + gap + 14 < viewSize.width
        sunAnchor = CGPoint(x: fitsOnRight ? box.maxX + gap : box.minX - gap, y: box.midY)
        hideFocusMarksLater()
    }

    /// Tells the camera what each side wants, so the flip button lands on the right one
    private func shareVideoFormats() {
        cameraManager.frontFormat = (frontVideoQuality == "4K", frontVideoFrameRate)
        cameraManager.backFormat = (backVideoQuality == "4K", backVideoFrameRate)
    }

    private func applyVideoFormat() {
        shareVideoFormats()
        cameraManager.setVideoFormat(fourK: videoQuality == "4K", frameRate: videoFrameRate)
    }

    /// "AE/AF LOCK" under the top row while a press-and-hold keeps focus and brightness,
    /// like the iPhone Camera
    private var lockPill: some View {
        Text("AE/AF LOCK")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 4))
            .transition(.opacity)
    }

    /// A finger kept still on the picture for 0.6 s locks focus and brightness on that spot
    private func holdToLock(viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($fingerOnPicture) { _, down, _ in down = true }
            .onChanged { drag in
                if holdTouchStart != drag.startLocation {
                    // A new finger went down
                    let spot = drag.startLocation
                    holdTouchStart = spot
                    holdFiredThisTouch = false
                    holdTimer?.cancel()
                    let timer = DispatchWorkItem {
                        guard fingerOnPicture, holdTouchStart == spot,
                              pinchStartZoom == nil, dragStartShift == nil else { return }
                        holdFiredThisTouch = true
                        handleFocusTap(at: spot, viewSize: viewSize, lock: true)
                    }
                    holdTimer = timer
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: timer)
                } else if abs(drag.translation.width) > 10 || abs(drag.translation.height) > 10 {
                    // The finger moved: a drag, not a hold
                    holdTimer?.cancel()
                }
            }
            .onEnded { _ in
                holdTimer?.cancel()
                holdTouchStart = nil
            }
    }

    /// The yellow square a tap leaves on something that is not a face. An estimate of the
    /// iPhone Camera's size.
    private static let tapSquareSide: CGFloat = 96

    /// Hides the square and the sun after 2 seconds, unless a newer tap or drag came in
    private func hideFocusMarksLater() {
        focusIndicatorID += 1
        let tapID = focusIndicatorID
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // While locked the square and the sun stay, as on the iPhone Camera
            if focusIndicatorID == tapID, !cameraManager.focusLocked {
                withAnimation(.easeOut(duration: 0.2)) {
                    tapSquarePoint = nil
                    sunAnchor = nil
                }
            }
        }
    }

    /// While the sun is showing, dragging up or down anywhere on the picture makes it
    /// brighter or darker, like the iPhone Camera. 90 points of finger travel = 1 stop.
    private var brightnessDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { drag in
                guard sunAnchor != nil, pinchStartZoom == nil else { return }
                let start = dragStartShift ?? cameraManager.brightnessShift
                dragStartShift = start
                focusIndicatorID += 1 // the sun stays while the finger is down
                cameraManager.setBrightnessShift(start - Float(drag.translation.height / 90))
            }
            .onEnded { _ in
                guard dragStartShift != nil else { return }
                dragStartShift = nil
                hideFocusMarksLater()
            }
    }

    /// Starts recording the moment the button is pressed, like the iPhone Camera app.
    private func startRecordingNow() {
        cameraManager.startRecording(quality: videoQuality)
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            recordingSeconds += 1
        }
        isRecording = true
        isRecordingPaused = false
        hasRecordedSegments = false
        thumbnailVideo = nil
        lastSavedVideoID = nil
        lastVideoURL = nil
    }

    private func animateCountdownNumber() {
        countdownScale = 1.2
        withAnimation(.easeOut(duration: 0.3)) {
            countdownScale = 1.0
        }
    }


    private func takePhoto() {
        // A press while the last photo is still being made is ignored (big photos take ~2 s),
        // and so is one while the camera is being changed: no real photo can be taken then
        guard isPhotoMode, !cameraManager.isTakingPhoto, !cameraManager.isCameraChanging else { return }
        Diagnostics.log("Photo", "Shutter pressed")
        HapticFeedback.impact()
        let thumbnailBefore = thumbnailPhoto
        let savedIDBefore = lastSavedPhotoID
        lastSavedPhotoID = nil
        // How the phone is held at the press decides which way up the photo is saved
        let heldAt = tilt.angle
        photoShot += 1
        let shot = photoShot
        // Like the iPhone Camera, the picture on screen at the press flies into the thumbnail
        // straight away and the real photo takes its place when it arrives (about 2 s for a
        // 24 MP one). It already carries the filter, skin smoothing and blur.
        // The shape and the Mirror selfies switch as they are at the press: the real photo
        // lands up to 2 s later, and a change made meanwhile must not reach back into it
        let shape = photoCropAspect
        let unmirror = cameraManager.isFrontCamera && !mirrorSelfies
        let quick = cameraManager.filteredPreview.map { Self.trimmed($0, toShape: shape) }
        capturedPhoto = quick
        withAnimation(.easeOut(duration: 0.1)) {
            showCaptureFlash = true
        }
        // Blink off, show the picture full screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showCaptureFlash = false
            guard shot == photoShot else { return }
            captureAnimationPhase = .fullScreen
        }
        // Animate to thumbnail
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard shot == photoShot else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                captureAnimationPhase = .thumbnail
            }
        }
        // Set thumbnail and hide animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard shot == photoShot else { return }
            if photoLandedShot != shot, let quick {
                thumbnailPhoto = quick.uprightForPhone(heldAt: heldAt)
            }
            captureAnimationPhase = .idle
        }
        cameraManager.capturePhoto { fullImage in
            guard let fullImage = fullImage else {
                photoLandedShot = shot
                // No photo came: the stand-in must not stay as if one had been saved
                if shot == photoShot {
                    thumbnailPhoto = thumbnailBefore
                    lastSavedPhotoID = savedIDBefore
                }
                Diagnostics.log("Photo", "No photo came; told the user nothing was saved")
                captureProblem = "The photo could not be taken, so nothing was saved. Please take it again."
                return
            }
            // Save what the screen showed: back camera = the whole 4:3 picture, selfie =
            // the same 9:16 framing as Video, selfie zoomed out = the whole picture
            // Flipping a selfie back redraws every pixel, so none of this runs on the
            // screen's thread (the live picture would freeze for a moment)
            Self.photoFinishing.async {
                let image = Self.trimmed(fullImage, toShape: shape)
                var saved = image.uprightForPhone(heldAt: heldAt)
                if unmirror { saved = saved.flippedSideToSide() }
                DispatchQueue.main.async {
                    photoLandedShot = shot
                    if shot == photoShot {
                        capturedPhoto = image
                        thumbnailPhoto = saved
                    }

                    // Save to library
                    savePhotoToLibrary(image: saved)
                }
            }
        }
    }

    /// Trims the camera frame to its centred area of the given shape,
    /// so the saved photo matches what was framed before the shutter.
    private static func centreCrop(_ image: UIImage, to previewSize: CGSize) -> UIImage {
        guard let cgImage = image.cgImage,
              previewSize.width > 0, previewSize.height > 0 else { return image }
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let scale = max(previewSize.width / imageWidth, previewSize.height / imageHeight)
        let visibleWidth = min(imageWidth, previewSize.width / scale)
        let visibleHeight = min(imageHeight, previewSize.height / scale)
        let cropRect = CGRect(x: (imageWidth - visibleWidth) / 2,
                              y: (imageHeight - visibleHeight) / 2,
                              width: visibleWidth,
                              height: visibleHeight).integral
        guard let cropped = cgImage.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    /// "Saved to Photos" in the middle of the screen for two seconds, shown only once
    /// Photos has really accepted the video.
    private func flashSavedMessage() {
        withAnimation(.easeOut(duration: 0.25)) { showSavedToast = true }
        // A second save while the words are up keeps them up for its own two seconds
        savedToastHide?.cancel()
        let hide = DispatchWorkItem {
            withAnimation(.easeIn(duration: 0.3)) { showSavedToast = false }
        }
        savedToastHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: hide)
    }

    // MARK: - A recording the app closed on

    /// Once per launch: was a recording cut short last time (a crash, or iOS ending the app)
    /// before it reached Photos? If so, offer to save what was recorded.
    private func lookForInterruptedRecording() {
        guard !lookedForInterrupted else { return }
        lookedForInterrupted = true
        DispatchQueue.global(qos: .userInitiated).async {
            let takes = VideoRecorder.interruptedTakes()
            guard !takes.isEmpty else { return }
            DispatchQueue.main.async {
                interruptedTakes = takes
                showInterruptedAlert = true
            }
        }
    }

    private var interruptedMessage: String {
        let seconds = Int(interruptedTakes.reduce(0) { $0 + $1.seconds }.rounded())
        let length: String
        if seconds < 60 {
            length = seconds == 1 ? "1 second" : "\(seconds) seconds"
        } else {
            length = "\(seconds / 60) min \(seconds % 60) s"
        }
        let what = interruptedTakes.count > 1 ? "\(interruptedTakes.count) videos were" : "your last video was"
        return "CinematiCam closed before \(what) saved. About \(length) was recovered. The last few seconds may be missing."
    }

    private func saveInterruptedRecordings() {
        let takes = interruptedTakes
        interruptedTakes = []
        for take in takes {
            VideoRecorder.join(take) { url in
                DispatchQueue.main.async {
                    if let url = url {
                        saveFinishedVideo(url)
                    } else {
                        captureProblem = "The interrupted recording could not be put back together. It will be offered again the next time you open CinematiCam."
                    }
                }
            }
        }
    }

    private func discardInterruptedRecordings() {
        interruptedTakes.forEach(VideoRecorder.remove)
        interruptedTakes = []
    }

    private func saveToPhotoLibrary(url: URL) {
        permissionsManager.requestPhotoLibraryPermission { granted in
            guard granted else { return }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("Video saved to Photos!")
                        flashSavedMessage()
                        VideoRecorder.markSaved(url)
                    } else {
                        print("Error saving to Photos: \(error?.localizedDescription ?? "unknown")")
                    }
                }
            }
        }
    }

    /// Saves a finished clip to Photos with no message, like the Camera app: the
    /// thumbnail beside the shutter is the confirmation. There is no preview screen to
    /// fall back on, so a failed save keeps the clip and tells the user.
    private func saveFinishedVideo(_ url: URL) {
        permissionsManager.requestPhotoLibraryPermission { granted in
            guard granted else {
                unsavedVideoURL = url
                showSaveFailedAlert = true
                return
            }
            var savedID: String?
            PHPhotoLibrary.shared().performChanges {
                savedID = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)?
                    .placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("Video saved to Photos!")
                        flashSavedMessage()
                        VideoRecorder.markSaved(url)
                        lastSavedVideoID = savedID
                        unsavedVideoURL = nil
                    } else {
                        print("Error saving to Photos: \(error?.localizedDescription ?? "unknown")")
                        unsavedVideoURL = url
                        showSaveFailedAlert = true
                    }
                }
            }
        }
    }

    private func savePhotoToLibrary(image: UIImage) {
        permissionsManager.requestPhotoLibraryPermission { granted in
            guard granted else {
                photoNotSaved(image)
                return
            }
            // Packing a 24 MP photo into a file takes a moment: not on the screen's thread,
            // or the live picture would freeze after every shot
            Self.photoFinishing.async {
                // Near-lossless JPEG so the full-size photo keeps its detail
                guard let data = image.jpegData(compressionQuality: 0.95) else {
                    DispatchQueue.main.async { photoNotSaved(image) }
                    return
                }
                var savedID: String?
                PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                    savedID = request.placeholderForCreatedAsset?.localIdentifier
                } completionHandler: { success, error in
                    DispatchQueue.main.async {
                        if success {
                            Diagnostics.log("Photo", "Saved to Photos")
                            lastSavedPhotoID = savedID
                            if unsavedPhoto === image { unsavedPhoto = nil }
                        } else {
                            Diagnostics.log("Photo", "Could not save to Photos: \(error?.localizedDescription ?? "unknown")")
                            photoNotSaved(image)
                        }
                    }
                }
            }
        }
    }

    /// A photo that Photos did not take is kept so the save can be tried again, and the
    /// user is told (the thumbnail alone would look as if it had been saved)
    private func photoNotSaved(_ image: UIImage) {
        unsavedPhoto = image
        showPhotoNotSavedAlert = true
    }

    // MARK: - Retouch Helper Properties

    /// Slow motion leaves the Mist glow out (no time per frame): its slider is greyed out there
    private var mistOffHere: Bool { selectedRetouchParam == 3 && slowTab }

    private var currentParamName: String {
        ["Natural", "Smooth", "Radius", "Mist"][selectedRetouchParam]
    }

    private var currentParamBinding: Binding<Float> {
        switch selectedRetouchParam {
        case 1: return $retouchAmount
        case 2: return $retouchRadius
        case 3: return Binding(get: { mistAmount }, set: { mistAmount = $0; cameraManager.mistAmount = $0 })
        default: return $retouchAmount
        }
    }

    private var currentParamRange: ClosedRange<Float> {
        switch selectedRetouchParam {
        case 1: return 0...1
        case 2: return 1...15
        default: return 0...1
        }
    }

    private var currentParamValueText: String {
        switch selectedRetouchParam {
        case 1: return "\(Int(retouchAmount * 100))%"
        case 2: return String(format: "%.1f", retouchRadius)
        case 3: return mistOffHere ? "Off" : "\(Int(mistAmount * 100))%"
        default: return ""
        }
    }

    private func updateCameraRetouchParams() {
        cameraManager.setRetouchAmount(retouchAmount)
        cameraManager.setRetouchRadius(retouchRadius)
        cameraManager.setSkinBrightness(0)
        cameraManager.setSkinWarmth(0)
    }
    // MARK: - Teleprompter Scrolling

    private func startTeleprompterScroll() {
        guard teleprompterEnabled, !teleprompterText.isEmpty else { return }
        teleprompterTimer?.invalidate()
        let pixelsPerTick = teleprompterScrollSpeed * 0.25
        teleprompterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            teleprompterScrollOffset += pixelsPerTick
        }
    }

    private func stopTeleprompterScroll() {
        teleprompterTimer?.invalidate()
        teleprompterTimer = nil
    }

    private func resetTeleprompterScroll() {
        stopTeleprompterScroll()
        teleprompterScrollOffset = 0
    }

    private func generateVideoThumbnail(from url: URL) {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, _ in
            if let cgImage = cgImage {
                DispatchQueue.main.async {
                    thumbnailVideo = UIImage(cgImage: cgImage)
                }
            }
        }
    }

    // MARK: - Caption Methods

    private func transcribeAndShowEditor() {
        guard let url = recordedVideoURL else { return }

        isTranscribing = true

        speechManager.transcribe(videoURL: url) { segments, error in
            isTranscribing = false

            if let segments = segments, !segments.isEmpty {
                captions = segments
                showCaptionEditor = true
            } else {
                // No speech detected or error
                print("Transcription failed or no speech: \(error?.localizedDescription ?? "no speech")")
                recordedVideoURL = nil
            }
        }
    }

    private func exportWithCaptions() {
        guard let url = recordedVideoURL else { return }

        showCaptionEditor = false
        isTranscribing = true

        captionRenderer.renderCaptions(videoURL: url, captions: captions) { outputURL, error in
            isTranscribing = false

            if let outputURL = outputURL {
                // Save the captioned version (original already saved)
                saveToPhotoLibrary(url: outputURL)
            } else {
                print("Caption render failed: \(error?.localizedDescription ?? "unknown")")
            }

            recordedVideoURL = nil
            captions = []
        }
    }
}

// MARK: - Capture Animation Phase
enum CaptureAnimationPhase {
    case idle
    case fullScreen
    case thumbnail
}

// MARK: - Volume Button Handler
class VolumeButtonHandler: ObservableObject {
    @Published var volumeButtonPressed = false
    private var audioSession: AVAudioSession?
    private var volumeObserver: NSKeyValueObservation?
    private var initialVolume: Float = 0.5
    private var isResettingVolume = false
    private var volumeView: MPVolumeView?
    private var volumeSlider: UISlider?
    private var suppressPressesUntil = Date.distantPast

    init() {
        // iOS 18+ uses Apple's camera-button event instead (CameraButtonModifier), which
        // fires only on real presses. Watching the volume level is a fallback for older
        // iOS: audio start-up (launch, returning to the app, closing the player) shifts
        // the volume and looks like a press, starting recordings by itself.
        if #available(iOS 18.0, *) { return }
        setupVolumeView()
        setupVolumeObserver()
    }

    /// Ignores volume changes for a while. Flipping cameras reconfigures the audio
    /// session, which shifts outputVolume and would otherwise look like a volume-button
    /// press (starting a recording).
    func suppressPresses(for duration: TimeInterval) {
        suppressPressesUntil = Date().addingTimeInterval(duration)
    }

    private func setupVolumeView() {
        // Create volume view once and keep reference to slider
        volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        volumeSlider = volumeView?.subviews.first(where: { $0 is UISlider }) as? UISlider
    }

    private func setupVolumeObserver() {
        audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession?.setActive(true)
            initialVolume = audioSession?.outputVolume ?? 0.5
        } catch {
            print("Failed to set audio session active: \(error)")
        }

        // Observe volume changes
        volumeObserver = audioSession?.observe(\.outputVolume, options: [.new, .old]) { [weak self] _, change in
            guard let self = self,
                  let newVolume = change.newValue,
                  let oldVolume = change.oldValue else { return }

            // Ignore if we're programmatically resetting volume
            guard !self.isResettingVolume else { return }

            // During a camera switch, treat the change as the new baseline, not a press
            if Date() < self.suppressPressesUntil {
                self.initialVolume = newVolume
                print("Volume change ignored during camera switch (\(oldVolume) -> \(newVolume))")
                return
            }

            // Detect volume button press (ignore small changes)
            if abs(newVolume - oldVolume) > 0.01 {
                // Reset volume FIRST, then trigger photo after a short delay
                self.resetVolume {
                    DispatchQueue.main.async {
                        self.volumeButtonPressed.toggle()
                    }
                }
            }
        }
    }

    private func resetVolume(completion: @escaping () -> Void) {
        isResettingVolume = true
        DispatchQueue.main.async {
            self.volumeSlider?.value = self.initialVolume
            // Wait for volume to settle, then trigger photo
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                completion()
                // Reset flag after completion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.isResettingVolume = false
                }
            }
        }
    }

    deinit {
        volumeObserver?.invalidate()
    }
}

/// Volume buttons (and Camera Control) via Apple's camera-button event on iOS 18+.
/// It reports only real presses and stops the system volume from changing.
struct CameraButtonModifier: ViewModifier {
    let onPress: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onCameraCaptureEvent { event in
                if event.phase == .ended { onPress() }
            }
        } else {
            content
        }
    }
}

#Preview {
    ContentView()
}
