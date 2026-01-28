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
    @State private var showSettings = false
    @AppStorage("selectedFilter") private var selectedFilterName = "Natural"
    @AppStorage("videoQuality") private var videoQuality = "1080p"
    @AppStorage("showGrid") private var showGrid = false
    @State private var filterIntensity: Double = 0.8
    @State private var retouchEnabled = false
    @State private var isPhotoMode = false
    @State private var capturedPhoto: UIImage?
    @State private var showPhotoPreview = false

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
    @State private var showCaptureFlash = false
    @State private var captureAnimationPhase: CaptureAnimationPhase = .idle

    // Inline retouch controls
    @State private var selectedRetouchParam = 0
    @State private var retouchAmount: Float = 0.5
    @State private var retouchRadius: Float = 9.0
    @State private var skinBrightness: Float = 0.0
    @State private var skinWarmth: Float = 0.0
    @State private var showUndoAlert = false
    @State private var showDiscardAlert = false
    @State private var showSwitchToPhotoAlert = false
    @State private var countdownValue: Int = 0
    @State private var countdownScale: CGFloat = 1.0
    @StateObject private var volumeHandler = VolumeButtonHandler()
    private let filters: [Filter] = [
        NaturalFilter(),
        WarmFilter(),
        CoolFilter(),
        VintageFilter(),
        BWFilter(),
        VividFilter()
    ]
    var body: some View {
        ZStack {
            // Raw camera preview (fallback)
            CameraPreviewView(session: cameraManager.captureSession)
                .ignoresSafeArea()

            // Filtered preview overlay
            if cameraManager.filteredPreview != nil {
                FilteredPreviewView(image: cameraManager.filteredPreview)
                    .ignoresSafeArea()
            }

            // Rule of thirds grid
            if showGrid {
                GeometryReader { geometry in
                    Path { path in
                        let width = geometry.size.width
                        let height = geometry.size.height

                        // Vertical lines
                        path.move(to: CGPoint(x: width / 3, y: 0))
                        path.addLine(to: CGPoint(x: width / 3, y: height))
                        path.move(to: CGPoint(x: width * 2 / 3, y: 0))
                        path.addLine(to: CGPoint(x: width * 2 / 3, y: height))

                        // Horizontal lines
                        path.move(to: CGPoint(x: 0, y: height / 3))
                        path.addLine(to: CGPoint(x: width, y: height / 3))
                        path.move(to: CGPoint(x: 0, y: height * 2 / 3))
                        path.addLine(to: CGPoint(x: width, y: height * 2 / 3))
                    }
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                }
                .ignoresSafeArea()
            }
        }
        // Teleprompter overlay
        .overlay {
            if teleprompterEnabled && !teleprompterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TeleprompterOverlayView(
                    text: teleprompterText,
                    scrollOffset: teleprompterScrollOffset,
                    onDismiss: {
                        teleprompterEnabled = false
                        resetTeleprompterScroll()
                    }
                )
            }
        }
        // Top right controls (flash, rotate, settings, retouch)
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 12) {
                // Flash button (only visible for back camera)
                if isBackCamera {
                    Button {
                        HapticFeedback.impact()
                        isFlashOn = cameraManager.toggleFlash()
                    } label: {
                        Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash")
                            .font(.title2)
                            .foregroundColor(isFlashOn ? .yellow : .white)
                            .padding(12)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .disabled(isRecording)
                }

                // Rotate camera
                Button {
                    HapticFeedback.impact()
                    cameraManager.switchCamera()
                    isBackCamera.toggle()
                } label: {
                    Image(systemName: "camera.rotate")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .disabled(isRecording)

                // Settings
                Button {
                    HapticFeedback.impact()
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .disabled(isRecording)

                // Retouch
                Button {
                    HapticFeedback.impact()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        retouchEnabled.toggle()
                    }
                    cameraManager.setRetouch(retouchEnabled)
                    if retouchEnabled {
                        updateCameraRetouchParams()
                    }
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.title2)
                        .foregroundColor(retouchEnabled ? .yellow : .white)
                        .padding(12)
                        .background(retouchEnabled ? Color.yellow.opacity(0.3) : Color.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .disabled(isRecording)

                // Teleprompter
                Button {
                    HapticFeedback.impact()
                    showTeleprompterSheet = true
                } label: {
                    Image(systemName: "text.justify.leading")
                        .font(.title2)
                        .foregroundColor(teleprompterEnabled ? .yellow : .white)
                        .padding(12)
                        .background(teleprompterEnabled ? Color.yellow.opacity(0.3) : Color.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .disabled(isRecording)
            }
            .padding(.trailing, 16)
            .padding(.top, 60)
            .opacity(isRecording ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: isRecording)
        }
        // Recording indicator (top center, vintage camcorder style)
        .overlay(alignment: .top) {
            if isRecording || isRecordingPaused {
                HStack(spacing: 6) {
                    if isRecordingPaused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        Text("PAUSED")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.yellow)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .opacity(recordingDotOpacity)
                        Text("REC")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                            .opacity(recordingDotOpacity)
                    }
                    Text(formatTime(recordingSeconds))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.6))
                .cornerRadius(6)
                .padding(.top, 20)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        recordingDotOpacity = 0.3
                    }
                }
                .onChange(of: isRecording) { recording in
                    if recording {
                        recordingDotOpacity = 1.0
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            recordingDotOpacity = 0.3
                        }
                    }
                }
                .onDisappear {
                    recordingDotOpacity = 1.0
                }
            }
        }
        // Bottom controls (filters, sliders, capture button)
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                // Retouch controls (when enabled)
                if retouchEnabled && !isRecording {
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            ForEach(0..<4) { index in
                                let paramIcons = ["wand.and.rays", "circle.hexagongrid", "sun.max", "thermometer.sun"]
                                let paramNames = ["Smooth", "Radius", "Glow", "Warmth"]
                                Button {
                                    HapticFeedback.impact()
                                    selectedRetouchParam = index
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

                        HStack {
                            Text(currentParamName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 55, alignment: .leading)
                            Slider(value: currentParamBinding, in: currentParamRange)
                                .tint(.yellow)
                                .onChange(of: retouchAmount) { _ in updateCameraRetouchParams() }
                                .onChange(of: retouchRadius) { _ in updateCameraRetouchParams() }
                                .onChange(of: skinBrightness) { _ in updateCameraRetouchParams() }
                                .onChange(of: skinWarmth) { _ in updateCameraRetouchParams() }
                            Text(currentParamValueText)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.yellow)
                                .frame(width: 45, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.horizontal, 8)
                    .transition(.opacity)
                }

                // Filter carousel
                if !isRecording {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<filters.count, id: \.self) { index in
                                Button {
                                    HapticFeedback.impact()
                                    selectedFilterName = filters[index].name
                                    cameraManager.setFilter(filters[index])
                                    cameraManager.setFilterIntensity(filterIntensity)
                                } label: {
                                    FilterThumbnailView(
                                        filter: filters[index],
                                        isSelected: selectedFilterName == filters[index].name
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                // Filter intensity slider
                if selectedFilterName != "Natural" && !isRecording {
                    HStack {
                        Image(systemName: "circle.lefthalf.filled")
                            .foregroundColor(.white.opacity(0.7))
                        Slider(value: $filterIntensity, in: 0...1)
                            .tint(.yellow)
                            .onChange(of: filterIntensity) { newValue in
                                cameraManager.setFilterIntensity(newValue)
                            }
                        Text("\(Int(filterIntensity * 100))%")
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 40)
                    }
                    .padding(.horizontal, 24)
                }

                // Photo/Video toggle slider
                if !isRecording {
                    HStack(spacing: 0) {
                        Button {
                            HapticFeedback.impact()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isPhotoMode = false
                            }
                        } label: {
                            Text("Video")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isPhotoMode ? .white.opacity(0.6) : .black)
                                .frame(width: 70, height: 32)
                                .background(
                                    Capsule()
                                        .fill(isPhotoMode ? Color.clear : Color.white)
                                )
                        }

                        Button {
                            HapticFeedback.impact()
                            if isRecordingPaused && hasRecordedSegments {
                                showSwitchToPhotoAlert = true
                            } else {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isPhotoMode = true
                                }
                            }
                        } label: {
                            Text("Photo")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isPhotoMode ? .black : .white.opacity(0.6))
                                .frame(width: 70, height: 32)
                                .background(
                                    Capsule()
                                        .fill(isPhotoMode ? Color.white : Color.clear)
                                )
                        }
                    }
                    .padding(4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.4))
                    )
                }

                // Recording controls - TikTok style
                if isPhotoMode {
                    // Photo capture button with thumbnail
                    // 3 slots to match video layout: [left] [center] [right]
                    HStack(spacing: 30) {
                        // Left slot: photo thumbnail
                        if let thumbnail = thumbnailPhoto, captureAnimationPhase == .idle {
                            Button {
                                openPhotosApp()
                            } label: {
                                Image(uiImage: thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                            }
                        } else {
                            Color.clear
                                .frame(width: 50, height: 50)
                        }

                        // Center: capture button
                        Button {
                            takePhoto()
                        } label: {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 80, height: 80)
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 64, height: 64)
                            }
                        }

                        // Right slot: empty spacer
                        Color.clear
                            .frame(width: 50, height: 50)
                    }
                    .padding(.bottom, 30)
                } else {
                    // Video recording controls - TikTok style
                    // 3 slots: [left] [center record] [right] to match photo layout
                    HStack(spacing: 30) {
                        // Left slot: fixed 50pt layout width, overflow visible
                        ZStack {
                            Color.clear
                                .frame(width: 50, height: 50)

                            if isRecordingPaused && hasRecordedSegments {
                                HStack(spacing: 8) {
                                    Button {
                                        HapticFeedback.impact()
                                        showDiscardAlert = true
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(Color.black.opacity(0.5))
                                                .frame(width: 40, height: 40)
                                            Image(systemName: "xmark")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    Button {
                                        HapticFeedback.impact()
                                        showUndoAlert = true
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(Color.black.opacity(0.5))
                                                .frame(width: 40, height: 40)
                                            Image(systemName: "arrow.uturn.backward")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                            } else if isRecording {
                                Button {
                                    HapticFeedback.impact()
                                    showDiscardAlert = true
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color.black.opacity(0.5))
                                            .frame(width: 50, height: 50)
                                        Image(systemName: "xmark")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            } else if let videoThumb = thumbnailVideo {
                                Button {
                                    openPhotosApp()
                                } label: {
                                    Image(uiImage: videoThumb)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 50, height: 50)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white, lineWidth: 2)
                                        )
                                }
                            }
                        }
                        .frame(width: 50, height: 50)

                        // Center: Record/Pause button
                        Button {
                            HapticFeedback.impact()
                            if isRecording {
                                cameraManager.pauseRecording()
                                recordingTimer?.invalidate()
                                recordingTimer = nil
                                isRecording = false
                                isRecordingPaused = true
                                hasRecordedSegments = true
                            } else if isRecordingPaused {
                                cameraManager.resumeRecording()
                                recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                                    recordingSeconds += 1
                                }
                                isRecording = true
                                isRecordingPaused = false
                            } else {
                                startRecordingWithCountdown()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .stroke(isRecording || isRecordingPaused ? Color.red.opacity(0.5) : Color.white, lineWidth: 4)
                                    .frame(width: 80, height: 80)

                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 64, height: 64)

                                if isRecording {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white)
                                        .frame(width: 8, height: 24)
                                        .offset(x: -8)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white)
                                        .frame(width: 8, height: 24)
                                        .offset(x: 8)
                                }
                            }
                        }
                        .disabled(countdownValue > 0)

                        // Right slot: Finish button (checkmark) when paused with segments
                        if isRecordingPaused && hasRecordedSegments {
                            Button {
                                HapticFeedback.impact()
                                cameraManager.stopRecording { url in
                                    if let url = url {
                                        generateVideoThumbnail(from: url)
                                        saveToPhotoLibrary(url: url)
                                    }
                                }
                                isRecording = false
                                isRecordingPaused = false
                                hasRecordedSegments = false
                                recordingSeconds = 0
                                resetTeleprompterScroll()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.red.opacity(0.8))
                                        .frame(width: 50, height: 50)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                        } else {
                            Color.clear
                                .frame(width: 50, height: 50)
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .padding(.bottom, 20)
        }
        .onAppear {
            permissionsManager.requestCameraPermission { granted in
                if granted {
                    cameraManager.configure()
                    cameraManager.startSession()
                    // Restore saved filter or default to Natural
                    let savedFilter = filters.first { $0.name == selectedFilterName } ?? filters[0]
                    cameraManager.setFilter(savedFilter)
                    cameraManager.setFilterIntensity(filterIntensity)
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
                    Section("Video") {
                        Picker("Quality", selection: $videoQuality) {
                            Text("4K").tag("4K")
                            Text("1080p").tag("1080p")
                            Text("720p").tag("720p")
                        }
                    }
                    Section("Guides") {
                        Toggle("Rule of Thirds Grid", isOn: $showGrid)
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
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    Text("\(countdownValue)")
                        .font(.system(size: 200, weight: .heavy, design: .rounded))
                        .foregroundColor(.red)
                        .scaleEffect(countdownScale)
                }
            }
        }
        // Video saved toast (keep for videos only)
        .overlay(alignment: .center) {
            if showSavedToast {
                Text("Video Saved!")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .transition(.opacity)
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
        .onChange(of: isRecording) { recording in
            if recording {
                startTeleprompterScroll()
            } else {
                stopTeleprompterScroll()
            }
        }
    }

    private func handleVolumeButtonPress() {
        guard countdownValue == 0 else { return }
        HapticFeedback.impact()

        if isPhotoMode {
            takePhoto()
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
                startRecordingWithCountdown()
            }
        }
    }

    private func startRecordingWithCountdown() {
        guard countdownValue == 0 else { return }
        countdownValue = 3
        countdownScale = 1.0
        AudioServicesPlaySystemSound(1113)
        animateCountdownNumber()

        func tick(remaining: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if remaining > 1 {
                    countdownScale = 1.0
                    countdownValue = remaining - 1
                    AudioServicesPlaySystemSound(1113)
                    animateCountdownNumber()
                    tick(remaining: remaining - 1)
                } else {
                    countdownValue = 0
                    // Start actual recording
                    cameraManager.startRecording(quality: videoQuality)
                    recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        recordingSeconds += 1
                    }
                    isRecording = true
                    isRecordingPaused = false
                    hasRecordedSegments = false
                    thumbnailVideo = nil
                }
            }
        }
        tick(remaining: 3)
    }

    private func animateCountdownNumber() {
        countdownScale = 1.2
        withAnimation(.easeOut(duration: 0.3)) {
            countdownScale = 1.0
        }
    }

    private func takePhoto() {
        guard isPhotoMode else { return }
        HapticFeedback.impact()
        cameraManager.capturePhoto { image in
            if let image = image {
                capturedPhoto = image

                // Start capture animation
                withAnimation(.easeOut(duration: 0.1)) {
                    showCaptureFlash = true
                }

                // Flash off, show full image
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showCaptureFlash = false
                    captureAnimationPhase = .fullScreen
                }

                // Animate to thumbnail
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        captureAnimationPhase = .thumbnail
                    }
                }

                // Set thumbnail and hide animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    thumbnailPhoto = image
                    captureAnimationPhase = .idle
                }

                // Save to library
                savePhotoToLibrary(image: image)
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
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
                        withAnimation {
                            showSavedToast = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showSavedToast = false
                            }
                        }
                    } else {
                        print("Error saving to Photos: \(error?.localizedDescription ?? "unknown")")
                    }
                }
            }
        }
    }

    private func savePhotoToLibrary(image: UIImage) {
        permissionsManager.requestPhotoLibraryPermission { granted in
            guard granted else { return }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("Photo saved to Photos!")
                    } else {
                        print("Error saving photo: \(error?.localizedDescription ?? "unknown")")
                    }
                }
            }
        }
    }

    // MARK: - Retouch Helper Properties

    private var currentParamName: String {
        ["Smooth", "Radius", "Glow", "Warmth"][selectedRetouchParam]
    }

    private var currentParamBinding: Binding<Float> {
        switch selectedRetouchParam {
        case 0: return $retouchAmount
        case 1: return $retouchRadius
        case 2: return $skinBrightness
        case 3: return $skinWarmth
        default: return $retouchAmount
        }
    }

    private var currentParamRange: ClosedRange<Float> {
        switch selectedRetouchParam {
        case 0: return 0...1
        case 1: return 1...15
        case 2: return -0.1...0.2
        case 3: return -0.3...0.3
        default: return 0...1
        }
    }

    private var currentParamValueText: String {
        switch selectedRetouchParam {
        case 0: return "\(Int(retouchAmount * 100))%"
        case 1: return String(format: "%.1f", retouchRadius)
        case 2: return String(format: "%+.0f%%", skinBrightness * 100)
        case 3: return String(format: "%+.0f", skinWarmth * 100)
        default: return ""
        }
    }

    private func updateCameraRetouchParams() {
        cameraManager.setRetouchAmount(retouchAmount)
        cameraManager.setRetouchRadius(retouchRadius)
        cameraManager.setSkinBrightness(skinBrightness)
        cameraManager.setSkinWarmth(skinWarmth)
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

    private func openPhotosApp() {
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url)
        }
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

    init() {
        setupVolumeView()
        setupVolumeObserver()
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

#Preview {
    ContentView()
}
