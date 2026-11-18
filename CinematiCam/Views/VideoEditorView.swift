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
                .padding(.top, 12)  // Minimal top padding - pushed up
                .padding(.bottom, 8)

                // Video preview - larger for better visibility
                SyncedVideoPlayerView(
                    url: videoURL,
                    player: $player,
                    isPlaying: $isPlaying
                )
                .aspectRatio(9/16, contentMode: .fit)
                .frame(height: 520)
                .cornerRadius(12)
                .clipped()
                .padding(.horizontal, 24)
                .padding(.top, 4)

                Spacer().frame(height: 12)

                // Timeline with fixed center playhead (TikTok style)
                TikTokStyleTimeline(
                    videoURL: videoURL,
                    videoDuration: videoDuration,
                    playheadPosition: $playheadPosition,
                    splitPoints: $splitPoints,
                    deletedSegments: $deletedSegments,
                    selectedSegment: $selectedSegment,
                    onPositionChange: { position in
                        seekToPosition(position)
                    }
                )
                .frame(height: 144)  // 20% larger again (was 120)
                .padding(.horizontal, 16)

                Spacer().frame(height: 24)  // Gap between timeline and tools

                // Tools row (below timeline)
                HStack(spacing: 35) {
                    // Play/Pause button
                    Button {
                        togglePlayback()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                            Text(isPlaying ? "Pause" : "Play")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                        }
                    }

                    // Split button - adds split at current playhead
                    Button {
                        addSplitAtPlayhead()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "scissors")
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                            Text("Split")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                        }
                    }

                    // Delete segment button (only when segment selected)
                    if selectedSegment != nil {
                        Button {
                            deleteSelectedSegment()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 15))
                                    .foregroundColor(.red)
                                Text("Delete")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    // Volume button
                    Button {
                        showVolumeSlider.toggle()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: volume == 0 ? "speaker.slash" : "speaker.wave.2")
                                .font(.system(size: 15))
                                .foregroundColor(showVolumeSlider ? .yellow : .white)
                            Text("Volume")
                                .font(.system(size: 11))
                                .foregroundColor(showVolumeSlider ? .yellow : .white)
                        }
                    }
                }
                .padding(.vertical, 8)

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

                Spacer().frame(height: 20)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
        .onChange(of: splitPoints) { _ in
            reconfigureDisplayLink()
        }
        .onChange(of: deletedSegments) { _ in
            reconfigureDisplayLink()
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
                        splitPoints: splitPoints,
                        deletedSegments: deletedSegments,
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

    private func reconfigureDisplayLink() {
        guard let player = player, videoDuration > 0 else { return }
        displayLinkController.controller.configure(
            player: player,
            duration: videoDuration,
            trimStart: trimStart,
            trimEnd: trimEnd,
            splitPoints: splitPoints,
            deletedSegments: deletedSegments,
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
    let videoDuration: Double

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

    // Pinch-to-zoom state
    @State private var zoomScale: CGFloat = 1.0  // Current zoom level (1.0 = normal, 2.0 = 2x zoomed in)
    @State private var lastZoomScale: CGFloat = 1.0  // Accumulated zoom from previous pinches
    @State private var currentThumbnailCount: Int = 15  // Track for regeneration

    // Constants - thumbnail size stays FIXED (never stretches)
    private let thumbnailWidth: CGFloat = 53
    private let thumbnailHeight: CGFloat = 80
    private let baseThumbnailCount: Int = 15
    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 4.0

    // COMPUTED: Number of thumbnails based on zoom (MORE thumbnails when zoomed in)
    private var thumbnailCount: Int {
        Int(CGFloat(baseThumbnailCount) * zoomScale)
    }

    // Compute visible segments (non-deleted) and their visual boundaries
    private var visibleSegments: [(index: Int, start: Double, end: Double)] {
        let validSplits = splitPoints.filter { $0 > 0 && $0 < 1 }.sorted()
        var segments: [(index: Int, start: Double, end: Double)] = []

        var lastPoint = 0.0
        for (i, split) in validSplits.enumerated() {
            if !deletedSegments.contains(i) {
                segments.append((index: i, start: lastPoint, end: split))
            }
            lastPoint = split
        }
        // Last segment
        let lastIndex = validSplits.count
        if !deletedSegments.contains(lastIndex) {
            segments.append((index: lastIndex, start: lastPoint, end: 1.0))
        }

        return segments
    }

    // Total visible duration (as fraction of original)
    private var visibleDuration: Double {
        visibleSegments.reduce(0) { $0 + ($1.end - $1.start) }
    }

    // Gap between segment cards (only when there are splits)
    private let segmentGap: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            // Calculate visible timeline width based on non-deleted segments
            let totalThumbnails = thumbnails.count > 0 ? thumbnails.count : baseThumbnailCount
            let visibleFraction = visibleDuration > 0 ? visibleDuration : 1.0
            let visibleThumbnailCount = max(1, Int(Double(totalThumbnails) * visibleFraction))
            // Content width (thumbnails only, no gaps)
            let contentWidth = thumbnailWidth * CGFloat(visibleThumbnailCount)
            // Add gaps between segments to get total timeline width
            let numGaps = max(0, visibleSegments.count - 1)
            let gapWidth = splitPoints.isEmpty ? 0 : segmentGap * CGFloat(numGaps)
            let timelineWidth = contentWidth + gapWidth
            let centerX = geometry.size.width / 2

            // Calculate the total offset (accumulated + current drag)
            let totalOffset = lastDragOffset + dragOffset

            ZStack {
                // Draggable timeline content (timestamps + thumbnails)
                VStack(spacing: 2) {
                    // Timestamp row (above thumbnails)
                    HStack(spacing: 0) {
                        if !isLoading && thumbnails.count > 0 {
                            let visibleThumbs = getVisibleThumbnails()
                            let showInterval = max(1, visibleThumbs.count / 10)
                            ForEach(0..<visibleThumbs.count, id: \.self) { i in
                                if i % showInterval == 0 {
                                    let timeInSeconds = videoDuration * visibleThumbs[i].originalPosition
                                    Text(formatTime(timeInSeconds))
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(.gray)
                                        .frame(width: thumbnailWidth * CGFloat(showInterval), alignment: .leading)
                                }
                            }
                        } else {
                            Color.clear.frame(width: timelineWidth, height: 14)
                        }
                    }
                    .frame(height: 14)

                    // Thumbnails row - each segment as its own bordered card (TikTok style)
                    HStack(spacing: splitPoints.isEmpty ? 0 : segmentGap) {  // Gap between segment cards only when there are splits
                        if isLoading {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: thumbnailWidth * CGFloat(baseThumbnailCount), height: thumbnailHeight)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white, lineWidth: 2)
                                )
                                .overlay {
                                    ProgressView()
                                        .tint(.white)
                                }
                        } else {
                            // Render each visible segment as its own bordered card
                            ForEach(visibleSegments, id: \.index) { segment in
                                let segmentThumbs = getThumbnailsForSegment(segment)

                                HStack(spacing: 0) {
                                    ForEach(0..<segmentThumbs.count, id: \.self) { i in
                                        let thumb = segmentThumbs[i]

                                        Image(uiImage: thumb.image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: thumbnailWidth, height: thumbnailHeight)
                                            .clipped()
                                    }
                                }
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            selectedSegment == segment.index ? Color.yellow : Color.white,
                                            lineWidth: selectedSegment == segment.index ? 3 : 2
                                        )
                                )
                                .onTapGesture {
                                    if selectedSegment == segment.index {
                                        selectedSegment = nil
                                    } else {
                                        selectedSegment = segment.index
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: thumbnailHeight)
                }
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

                            // Update LOCAL state only (not the binding) - prevents multiple binding updates per frame
                            localDragPosition = Double(currentClampedOffset / timelineWidth)

                            // Map pixel offset back to original video position for seeking (accounts for gaps)
                            let originalPosition = calculateOriginalPosition(from: currentClampedOffset, contentWidth: contentWidth)
                            onPositionChange?(originalPosition)
                        }
                        .onEnded { value in
                            // Accumulate the drag offset
                            lastDragOffset += value.translation.width

                            // Clamp lastDragOffset so timeline stays in bounds
                            lastDragOffset = max(-timelineWidth, min(0, lastDragOffset))

                            dragOffset = 0

                            // Commit final position to binding (accounts for gaps)
                            let finalClampedOffset = max(0, min(timelineWidth, -lastDragOffset))
                            let finalOriginalPosition = calculateOriginalPosition(from: finalClampedOffset, contentWidth: contentWidth)
                            playheadPosition = finalOriginalPosition
                            onPositionChange?(finalOriginalPosition)

                            // Clear local state and drag flag
                            localDragPosition = nil
                            isDragging = false
                        }
                )
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            // Calculate new zoom scale
                            let newScale = lastZoomScale * value
                            zoomScale = min(max(newScale, minZoom), maxZoom)
                        }
                        .onEnded { value in
                            lastZoomScale = zoomScale

                            // Regenerate thumbnails if count changed
                            let newCount = Int(CGFloat(baseThumbnailCount) * zoomScale)
                            if newCount != currentThumbnailCount {
                                // Adjust offset to keep playhead position stable (accounts for gaps)
                                let visibleFraction = visibleDuration > 0 ? visibleDuration : 1.0
                                let newVisibleCount = max(1, Int(Double(newCount) * visibleFraction))
                                let newContentWidth = thumbnailWidth * CGFloat(newVisibleCount)
                                lastDragOffset = -calculatePixelOffset(for: playheadPosition, contentWidth: newContentWidth)

                                currentThumbnailCount = newCount
                                regenerateThumbnails(count: newCount)
                            }
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
                        .frame(width: 2, height: thumbnailHeight + 14 + 2)

                    // Bottom handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                }
                .position(x: centerX, y: geometry.size.height / 2)
            }
            .clipped()
            // Sync timeline position when playhead changes externally (e.g., during playback)
            .onChange(of: playheadPosition) { newValue in
                // Skip sync during dragging or when local drag position is active
                guard !isDragging, localDragPosition == nil else { return }

                // Calculate pixel offset accounting for gaps between segments
                let expectedOffset = -calculatePixelOffset(for: newValue, contentWidth: contentWidth)

                // Only sync if the change is significant (avoids feedback loops)
                if abs(expectedOffset - lastDragOffset) > 1 {
                    // Direct update - NO animation (CADisplayLink handles smooth updates)
                    lastDragOffset = expectedOffset
                    dragOffset = 0
                }
            }
        }
        .onAppear {
            generateThumbnails(count: baseThumbnailCount)
        }
    }

    // Helper struct for visible thumbnails
    private struct VisibleThumbnail {
        let image: UIImage
        let segmentIndex: Int
        let originalPosition: Double  // Position in original video (0-1)
    }

    // Get thumbnails that belong to non-deleted segments
    private func getVisibleThumbnails() -> [VisibleThumbnail] {
        guard thumbnails.count > 0 else { return [] }

        var result: [VisibleThumbnail] = []
        for (index, image) in thumbnails.enumerated() {
            let position = Double(index) / Double(thumbnails.count)
            let segmentIndex = getSegmentIndex(for: position)

            // Only include if segment is not deleted
            if !deletedSegments.contains(segmentIndex) {
                result.append(VisibleThumbnail(image: image, segmentIndex: segmentIndex, originalPosition: position))
            }
        }
        return result
    }

    // Get thumbnails for a specific segment
    private func getThumbnailsForSegment(_ segment: (index: Int, start: Double, end: Double)) -> [VisibleThumbnail] {
        guard thumbnails.count > 0 else { return [] }

        var result: [VisibleThumbnail] = []
        for (index, image) in thumbnails.enumerated() {
            let position = Double(index) / Double(thumbnails.count)

            // Check if this thumbnail falls within the segment's boundaries
            // Use a small epsilon for boundary comparison to handle edge cases
            if position >= segment.start && position < segment.end {
                result.append(VisibleThumbnail(image: image, segmentIndex: segment.index, originalPosition: position))
            }
        }

        // Handle edge case: if segment.end is 1.0, include the last thumbnail
        if segment.end >= 1.0 && !result.isEmpty {
            // Already handled by the loop
        } else if segment.end >= 1.0 && result.isEmpty && thumbnails.count > 0 {
            // Include at least the last thumbnail for the final segment
            let lastIndex = thumbnails.count - 1
            let position = Double(lastIndex) / Double(thumbnails.count)
            if getSegmentIndex(for: position) == segment.index {
                result.append(VisibleThumbnail(image: thumbnails[lastIndex], segmentIndex: segment.index, originalPosition: position))
            }
        }

        return result
    }

    // Get the visual bounds (offset and width) of a segment in the visible timeline
    private func getVisibleSegmentBounds(for segmentIndex: Int, timelineWidth: CGFloat) -> (offset: CGFloat, width: CGFloat)? {
        let validSplits = splitPoints.filter { $0 > 0 && $0 < 1 }.sorted()

        // Find the segment's original boundaries
        var segmentStart: Double = 0
        var segmentEnd: Double = 1

        if segmentIndex == 0 {
            segmentStart = 0
            segmentEnd = validSplits.first ?? 1
        } else if segmentIndex == validSplits.count {
            segmentStart = validSplits.last ?? 0
            segmentEnd = 1
        } else if segmentIndex > 0 && segmentIndex <= validSplits.count {
            segmentStart = validSplits[segmentIndex - 1]
            segmentEnd = segmentIndex < validSplits.count ? validSplits[segmentIndex] : 1
        }

        // Calculate how much visible content comes before this segment
        var visualOffset: Double = 0
        for seg in visibleSegments {
            if seg.index == segmentIndex {
                break
            }
            visualOffset += (seg.end - seg.start)
        }

        // Calculate segment's visual width
        let segmentDuration = segmentEnd - segmentStart
        let visualWidth = (segmentDuration / visibleDuration) * Double(timelineWidth)
        let visualOffsetPx = (visualOffset / visibleDuration) * Double(timelineWidth)

        return (offset: CGFloat(visualOffsetPx), width: CGFloat(visualWidth))
    }

    // Get X positions for split lines in the visible timeline
    private func getVisibleSplitPositions(timelineWidth: CGFloat) -> [CGFloat] {
        var positions: [CGFloat] = []
        var accumulatedWidth: CGFloat = 0

        for (i, seg) in visibleSegments.enumerated() {
            let segmentWidth = CGFloat((seg.end - seg.start) / visibleDuration) * timelineWidth
            accumulatedWidth += segmentWidth

            // Add split line after each segment except the last
            if i < visibleSegments.count - 1 {
                positions.append(accumulatedWidth - 1.5)  // Center the 3px line
            }
        }

        return positions
    }

    // Map visual timeline position (0-1) to original video position (0-1)
    private func mapVisualToOriginalPosition(_ visualPos: Double) -> Double {
        guard visibleDuration > 0 else { return visualPos }

        var accumulatedVisual: Double = 0
        for seg in visibleSegments {
            let segVisualDuration = (seg.end - seg.start) / visibleDuration
            if accumulatedVisual + segVisualDuration >= visualPos {
                // Position is within this segment
                let posWithinSegment = (visualPos - accumulatedVisual) / segVisualDuration
                return seg.start + posWithinSegment * (seg.end - seg.start)
            }
            accumulatedVisual += segVisualDuration
        }

        // Fallback: return end of last visible segment
        return visibleSegments.last?.end ?? visualPos
    }

    // Map original video position (0-1) to visual timeline position (0-1)
    // Note: This returns position within content only (doesn't account for gaps)
    private func mapOriginalToVisualPosition(_ originalPos: Double) -> Double {
        guard visibleDuration > 0 else { return originalPos }

        var visualPos: Double = 0
        for seg in visibleSegments {
            if originalPos >= seg.start && originalPos <= seg.end {
                // Position is within this segment
                let posWithinSegment = (originalPos - seg.start) / (seg.end - seg.start)
                let segVisualDuration = (seg.end - seg.start) / visibleDuration
                return visualPos + posWithinSegment * segVisualDuration
            } else if originalPos > seg.end {
                // Position is past this segment, add its full visual duration
                visualPos += (seg.end - seg.start) / visibleDuration
            }
        }

        return min(1.0, visualPos)
    }

    // Calculate pixel offset for a given original position (accounts for gaps between segments)
    private func calculatePixelOffset(for originalPos: Double, contentWidth: CGFloat) -> CGFloat {
        guard visibleDuration > 0 else { return CGFloat(originalPos) * contentWidth }

        var pixelOffset: CGFloat = 0
        let actualGap = splitPoints.isEmpty ? 0 : segmentGap

        for (index, seg) in visibleSegments.enumerated() {
            let segmentContentWidth = CGFloat((seg.end - seg.start) / visibleDuration) * contentWidth

            if originalPos >= seg.start && originalPos <= seg.end {
                // Position is within this segment
                let posWithinSegment = (originalPos - seg.start) / (seg.end - seg.start)
                return pixelOffset + CGFloat(posWithinSegment) * segmentContentWidth
            } else if originalPos > seg.end {
                // Position is past this segment, add its width plus gap
                pixelOffset += segmentContentWidth
                if index < visibleSegments.count - 1 {
                    pixelOffset += actualGap
                }
            }
        }

        return pixelOffset
    }

    // Calculate original video position from a pixel offset (reverse of calculatePixelOffset)
    private func calculateOriginalPosition(from pixelOffset: CGFloat, contentWidth: CGFloat) -> Double {
        guard visibleDuration > 0, contentWidth > 0 else { return Double(pixelOffset / max(1, contentWidth)) }

        var accumulatedOffset: CGFloat = 0
        let actualGap = splitPoints.isEmpty ? 0 : segmentGap

        for (index, seg) in visibleSegments.enumerated() {
            let segmentContentWidth = CGFloat((seg.end - seg.start) / visibleDuration) * contentWidth
            let segmentEndOffset = accumulatedOffset + segmentContentWidth

            if pixelOffset <= segmentEndOffset {
                // Position is within this segment
                let offsetWithinSegment = pixelOffset - accumulatedOffset
                let posWithinSegment = Double(offsetWithinSegment / segmentContentWidth)
                return seg.start + posWithinSegment * (seg.end - seg.start)
            }

            accumulatedOffset = segmentEndOffset

            // Check if pixel is in the gap AFTER this segment
            if index < visibleSegments.count - 1 {
                let gapEnd = accumulatedOffset + actualGap
                if pixelOffset < gapEnd {
                    // Pixel is in the gap - snap to END of current segment
                    return seg.end
                }
                accumulatedOffset = gapEnd
            }
        }

        // Fallback: return end of last visible segment
        return visibleSegments.last?.end ?? 1.0
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

    // Format seconds as M:SS
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func generateThumbnails(count: Int) {
        isLoading = true
        let targetCount = count

        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)  // Higher res for retina displays

        Task {
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)

            var times: [NSValue] = []
            for i in 0..<targetCount {
                let time = CMTime(seconds: durationSeconds * Double(i) / Double(targetCount), preferredTimescale: 600)
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

    private func regenerateThumbnails(count: Int) {
        generateThumbnails(count: count)
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
