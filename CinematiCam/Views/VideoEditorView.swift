//
//  VideoEditorView.swift
//  CinematiCam
//
//  Created by Abhishek Dangol on 1/29/26.
//

import SwiftUI
import AVFoundation
import UIKit

struct VideoEditorView: View {
    let videoURL: URL
    let onCancel: () -> Void
    let onExport: ([Double], Set<Int>, Double, Double, Double) -> Void  // splitPoints, deletedSegments, trimStart, trimEnd, volume

    @State private var trimStart: Double = 0.0
    @State private var trimEnd: Double = 1.0

    // Playhead position (0.0 to 1.0) - controlled by timeline scroll
    @State private var playheadPosition: Double = 0.0

    // Multiple splits support
    @State private var splitPoints: [Double] = []  // Array of split positions (0-1)
    @State private var deletedSegments: Set<Int> = []  // Which segments are deleted
    @State private var selectedSegment: Int? = nil  // Currently selected segment

    // Volume control
    @State private var volume: Double = 1.0  // 0.0 to 1.0
    @State private var showVolumeSlider: Bool = false

    // Player state
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = false
    @StateObject private var displayLinkController = DisplayLinkControllerWrapper()
    @State private var videoDuration: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with Cancel and Export
                HStack {
                    Button {
                        cleanupPlayer()
                        onCancel()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Text("Edit")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Button {
                        cleanupPlayer()
                        onExport(splitPoints, deletedSegments, trimStart, trimEnd, volume)
                    } label: {
                        Text("Export")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.yellow)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Video preview - smaller and at top (TikTok style)
                SyncedVideoPlayerView(
                    url: videoURL,
                    player: $player,
                    isPlaying: $isPlaying
                )
                .aspectRatio(9/16, contentMode: .fit)
                .frame(height: 400)
                .cornerRadius(12)
                .clipped()
                .padding(.horizontal, 40)
                .padding(.top, 10)

                Spacer()

                // Tools row
                HStack(spacing: 40) {
                    // Play/Pause button
                    Button {
                        togglePlayback()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                            Text(isPlaying ? "Pause" : "Play")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                        }
                    }

                    // Split button - adds split at current playhead
                    Button {
                        addSplitAtPlayhead()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "scissors")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                            Text("Split")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                        }
                    }

                    // Delete segment button (only when segment selected)
                    if selectedSegment != nil {
                        Button {
                            deleteSelectedSegment()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 24))
                                    .foregroundColor(.red)
                                Text("Delete")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    // Volume button
                    Button {
                        showVolumeSlider.toggle()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: volume == 0 ? "speaker.slash" : "speaker.wave.2")
                                .font(.system(size: 24))
                                .foregroundColor(showVolumeSlider ? .yellow : .white)
                            Text("Volume")
                                .font(.system(size: 12))
                                .foregroundColor(showVolumeSlider ? .yellow : .white)
                        }
                    }
                }
                .padding(.vertical, 16)

                // Volume slider (when visible)
                if showVolumeSlider {
                    HStack {
                        Button {
                            volume = 0
                        } label: {
                            Image(systemName: "speaker.slash")
                                .foregroundColor(.white)
                        }
                        Slider(value: $volume, in: 0...1)
                            .tint(.yellow)
                        Text("\(Int(volume * 100))%")
                            .foregroundColor(.white)
                            .frame(width: 45)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                // Split info text
                if !splitPoints.isEmpty {
                    Text("\(splitPoints.count) split\(splitPoints.count == 1 ? "" : "s") • \(segments.count - deletedSegments.count) segments")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .padding(.bottom, 8)
                }

                // Timeline with fixed center playhead (TikTok style)
                TikTokStyleTimeline(
                    videoURL: videoURL,
                    playheadPosition: $playheadPosition,
                    splitPoints: $splitPoints,
                    deletedSegments: $deletedSegments,
                    selectedSegment: $selectedSegment,
                    onPositionChange: { position in
                        seekToPosition(position)
                    }
                )
                .frame(height: 80)
                .padding(.horizontal, 16)

                Spacer().frame(height: 40)
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }

    // Calculate segments from split points
    private var segments: [(start: Double, end: Double)] {
        var result: [(Double, Double)] = []
        var lastPoint = trimStart

        let validSplits = splitPoints.filter { $0 > trimStart && $0 < trimEnd }.sorted()

        for split in validSplits {
            result.append((lastPoint, split))
            lastPoint = split
        }
        result.append((lastPoint, trimEnd))

        return result
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        let newPlayer = AVPlayer(url: videoURL)
        player = newPlayer

        // Start PAUSED at the beginning (TikTok style)
        newPlayer.pause()
        isPlaying = false
        playheadPosition = 0.0

        // Get video duration and configure DisplayLink
        Task {
            let asset = AVAsset(url: videoURL)
            let duration = try? await asset.load(.duration)
            if let duration = duration {
                await MainActor.run {
                    videoDuration = CMTimeGetSeconds(duration)

                    displayLinkController.controller.configure(
                        player: newPlayer,
                        duration: videoDuration,
                        trimStart: trimStart,
                        trimEnd: trimEnd,
                        onPositionUpdate: { position in
                            guard self.isPlaying else { return }
                            self.playheadPosition = position
                        },
                        onPlaybackEnded: {
                            self.player?.pause()
                            self.isPlaying = false
                            self.displayLinkController.controller.stop()

                            let startTime = CMTime(seconds: self.videoDuration * self.trimStart, preferredTimescale: 600)
                            self.player?.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
                            self.playheadPosition = self.trimStart
                        }
                    )
                }
            }
        }
    }

    private func cleanupPlayer() {
        displayLinkController.controller.stop()
        player?.pause()
        player = nil
    }

    private func togglePlayback() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            displayLinkController.controller.stop()
        } else {
            player.play()
            displayLinkController.controller.start()
        }
        isPlaying.toggle()
    }

    private func seekToPosition(_ position: Double) {
        guard let player = player, videoDuration > 0 else { return }
        let time = CMTime(seconds: videoDuration * position, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Split Actions

    private func addSplitAtPlayhead() {
        // Don't add split too close to existing ones or trim boundaries
        let minGap = 0.03

        // Check if too close to trim boundaries
        if playheadPosition < trimStart + minGap || playheadPosition > trimEnd - minGap {
            return
        }

        // Check if too close to existing split
        for split in splitPoints {
            if abs(split - playheadPosition) < minGap {
                return
            }
        }

        // Add the split and sort
        splitPoints.append(playheadPosition)
        splitPoints.sort()

        // Clear selection when adding split
        selectedSegment = nil
    }

    private func deleteSelectedSegment() {
        guard let selected = selectedSegment else { return }
        deletedSegments.insert(selected)
        selectedSegment = nil
    }
}

// MARK: - TikTok Style Timeline (Fixed Center Playhead, Drag Gesture)

struct TikTokStyleTimeline: View {
    let videoURL: URL
    let thumbnailCount: Int = 15

    @Binding var playheadPosition: Double
    @Binding var splitPoints: [Double]
    @Binding var deletedSegments: Set<Int>
    @Binding var selectedSegment: Int?

    var onPositionChange: ((Double) -> Void)?

    @State private var thumbnails: [UIImage] = []
    @State private var isLoading = true
    @State private var dragOffset: CGFloat = 0  // Current drag offset
    @State private var lastDragOffset: CGFloat = 0  // Accumulated offset from previous drags
    @State private var isDragging: Bool = false  // Track drag state to prevent onChange feedback loop
    @State private var localDragPosition: Double? = nil  // Position during active drag (avoids binding updates every frame)

    private let thumbnailWidth: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            let timelineWidth = thumbnailWidth * CGFloat(thumbnailCount)
            let centerX = geometry.size.width / 2

            // Calculate the total offset (accumulated + current drag)
            let totalOffset = lastDragOffset + dragOffset

            // Timeline position based on offset (clamped to 0...timelineWidth)
            let clampedOffset = max(0, min(timelineWidth, -totalOffset))
            let position = clampedOffset / timelineWidth

            ZStack {
                // Draggable timeline content
                ZStack(alignment: .leading) {
                    // Thumbnails
                    HStack(spacing: 0) {
                        if isLoading {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: timelineWidth, height: 50)
                                .overlay {
                                    ProgressView()
                                        .tint(.white)
                                }
                        } else {
                            ForEach(0..<thumbnails.count, id: \.self) { index in
                                let segmentIndex = getSegmentIndex(for: Double(index) / Double(thumbnailCount))

                                Image(uiImage: thumbnails[index])
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: thumbnailWidth, height: 50)
                                    .clipped()
                                    .overlay {
                                        // Deleted segment overlay
                                        if deletedSegments.contains(segmentIndex) {
                                            Color.black.opacity(0.7)
                                            Image(systemName: "xmark")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.red)
                                        }
                                        // Selected segment highlight
                                        else if selectedSegment == segmentIndex {
                                            Color.yellow.opacity(0.2)
                                        }
                                    }
                                    .onTapGesture {
                                        if deletedSegments.contains(segmentIndex) {
                                            // Restore deleted segment
                                            deletedSegments.remove(segmentIndex)
                                            selectedSegment = nil
                                        } else if selectedSegment == segmentIndex {
                                            // Deselect
                                            selectedSegment = nil
                                        } else {
                                            // Select segment
                                            selectedSegment = segmentIndex
                                        }
                                    }
                            }
                        }
                    }

                    // Split lines
                    ForEach(splitPoints.indices, id: \.self) { index in
                        let split = splitPoints[index]
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 3, height: 50)
                            .offset(x: timelineWidth * split)
                    }
                }
                .frame(height: 50)
                // Position timeline so playhead aligns with center
                .offset(x: centerX + totalOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            dragOffset = value.translation.width

                            // Calculate position for visual feedback
                            let currentTotalOffset = lastDragOffset + dragOffset
                            let currentClampedOffset = max(0, min(timelineWidth, -currentTotalOffset))
                            let currentPosition = currentClampedOffset / timelineWidth

                            // Update LOCAL state only (not the binding) - prevents multiple binding updates per frame
                            localDragPosition = currentPosition

                            // Still seek video for preview
                            onPositionChange?(currentPosition)
                        }
                        .onEnded { value in
                            // Accumulate the drag offset
                            lastDragOffset += value.translation.width

                            // Clamp lastDragOffset so timeline stays in bounds
                            lastDragOffset = max(-timelineWidth, min(0, lastDragOffset))

                            dragOffset = 0

                            // Commit final position to binding (single update at end of drag)
                            let finalPosition = max(0, min(1, -lastDragOffset / timelineWidth))
                            playheadPosition = finalPosition
                            onPositionChange?(finalPosition)

                            // Clear local state and drag flag
                            localDragPosition = nil
                            isDragging = false
                        }
                )

                // Fixed center playhead (white line)
                VStack(spacing: 0) {
                    // Top handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)

                    // Vertical line
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 50)

                    // Bottom handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                }
                .position(x: centerX, y: geometry.size.height / 2)
            }
            .cornerRadius(8)
            .clipped()
            // Sync timeline position when playhead changes externally (e.g., during playback)
            .onChange(of: playheadPosition) { newValue in
                // Skip sync during dragging or when local drag position is active
                guard !isDragging, localDragPosition == nil else { return }
                // Only sync if the change is significant (avoids feedback loops)
                let expectedOffset = -newValue * timelineWidth
                if abs(expectedOffset - lastDragOffset) > 1 {
                    // Direct update - NO animation (CADisplayLink handles smooth updates)
                    lastDragOffset = expectedOffset
                    dragOffset = 0
                }
            }
        }
        .onAppear {
            generateThumbnails()
        }
    }

    // Get which segment a position belongs to
    private func getSegmentIndex(for position: Double) -> Int {
        let validSplits = splitPoints.filter { $0 > 0 && $0 < 1 }.sorted()

        for (index, split) in validSplits.enumerated() {
            if position < split {
                return index
            }
        }
        return validSplits.count
    }

    private func generateThumbnails() {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 100, height: 100)

        Task {
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)

            var times: [NSValue] = []
            for i in 0..<thumbnailCount {
                let time = CMTime(seconds: durationSeconds * Double(i) / Double(thumbnailCount), preferredTimescale: 600)
                times.append(NSValue(time: time))
            }

            var generatedThumbnails: [UIImage] = []

            await withCheckedContinuation { continuation in
                var completed = 0
                generator.generateCGImagesAsynchronously(forTimes: times) { _, cgImage, _, _, _ in
                    if let cgImage = cgImage {
                        generatedThumbnails.append(UIImage(cgImage: cgImage))
                    }
                    completed += 1
                    if completed == times.count {
                        continuation.resume()
                    }
                }
            }

            await MainActor.run {
                thumbnails = generatedThumbnails
                isLoading = false
            }
        }
    }
}


// MARK: - Synced Video Player View

struct SyncedVideoPlayerView: UIViewRepresentable {
    let url: URL
    @Binding var player: AVPlayer?
    @Binding var isPlaying: Bool

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if let player = player, uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    static func dismantleUIView(_ uiView: PlayerUIView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }

    class PlayerUIView: UIView {
        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }
    }
}
