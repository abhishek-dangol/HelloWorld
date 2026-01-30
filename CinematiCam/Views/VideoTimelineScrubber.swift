//
//  VideoTimelineScrubber.swift
//  CinematiCam
//
//  Created by Abhishek Dangol on 1/29/26.
//

import SwiftUI
import AVFoundation
import UIKit

struct VideoTimelineScrubber: View {
    let videoURL: URL
    let thumbnailCount: Int = 10

    @Binding var trimStart: Double  // 0.0 to 1.0
    @Binding var trimEnd: Double    // 0.0 to 1.0

    // Playhead position (synced with video)
    @Binding var playheadPosition: Double  // 0.0 to 1.0

    // Multiple splits support
    @Binding var splitPoints: [Double]  // Array of split positions (0-1)
    @Binding var deletedSegments: Set<Int>  // Which segments are deleted
    @Binding var selectedSegment: Int?  // Currently selected segment for deletion

    // Callback when playhead is dragged
    var onPlayheadDrag: ((Double) -> Void)?

    @State private var thumbnails: [UIImage] = []
    @State private var isLoading = true
    @State private var isDraggingPlayhead = false

    private let handleWidth: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width

            ZStack {
                if isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            ProgressView()
                                .tint(.white)
                        }
                } else {
                    // Thumbnail strip
                    HStack(spacing: 0) {
                        ForEach(0..<thumbnails.count, id: \.self) { index in
                            Image(uiImage: thumbnails[index])
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: totalWidth / CGFloat(thumbnailCount), height: geometry.size.height)
                                .clipped()
                        }
                    }

                    // Dimmed areas outside trim range
                    HStack(spacing: 0) {
                        // Left dimmed area
                        Rectangle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: totalWidth * trimStart)

                        Spacer()

                        // Right dimmed area
                        Rectangle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: totalWidth * (1 - trimEnd))
                    }

                    // Segment overlays (for selection and deletion)
                    ForEach(0..<segments.count, id: \.self) { index in
                        let segment = segments[index]
                        let segmentWidth = totalWidth * (segment.end - segment.start)
                        let segmentCenterX = totalWidth * (segment.start + segment.end) / 2

                        Rectangle()
                            .fill(deletedSegments.contains(index) ? Color.black.opacity(0.7) : (selectedSegment == index ? Color.yellow.opacity(0.2) : Color.clear))
                            .frame(width: segmentWidth, height: geometry.size.height)
                            .position(x: segmentCenterX, y: geometry.size.height / 2)
                            .overlay {
                                if deletedSegments.contains(index) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.red)
                                        .position(x: segmentCenterX, y: geometry.size.height / 2)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if deletedSegments.contains(index) {
                                    // Restore deleted segment
                                    deletedSegments.remove(index)
                                    selectedSegment = nil
                                } else if selectedSegment == index {
                                    // Deselect
                                    selectedSegment = nil
                                } else {
                                    // Select segment
                                    selectedSegment = index
                                }
                            }
                    }

                    // Split lines at each split point
                    ForEach(splitPoints.indices, id: \.self) { index in
                        let split = splitPoints[index]
                        if split > trimStart && split < trimEnd {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 3, height: geometry.size.height)
                                .position(x: totalWidth * split, y: geometry.size.height / 2)
                        }
                    }

                    // Trim selection border (yellow)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.yellow, lineWidth: 3)
                        .frame(width: totalWidth * (trimEnd - trimStart))
                        .position(x: totalWidth * (trimStart + trimEnd) / 2, y: geometry.size.height / 2)

                    // Selected segment highlight border
                    if let selected = selectedSegment, selected < segments.count {
                        let segment = segments[selected]
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: totalWidth * (segment.end - segment.start) - 4, height: geometry.size.height - 4)
                            .position(x: totalWidth * (segment.start + segment.end) / 2, y: geometry.size.height / 2)
                    }

                    // Left trim handle
                    handleView(isLeft: true)
                        .position(x: totalWidth * trimStart, y: geometry.size.height / 2)
                        .gesture(
                            DragGesture(coordinateSpace: .named("timeline"))
                                .onChanged { value in
                                    let newStart = max(0, min(value.location.x / totalWidth, trimEnd - 0.1))
                                    trimStart = newStart
                                    // Remove split points outside new trim range
                                    splitPoints = splitPoints.filter { $0 > trimStart && $0 < trimEnd }
                                }
                        )

                    // Right trim handle
                    handleView(isLeft: false)
                        .position(x: totalWidth * trimEnd, y: geometry.size.height / 2)
                        .gesture(
                            DragGesture(coordinateSpace: .named("timeline"))
                                .onChanged { value in
                                    let newEnd = max(trimStart + 0.1, min(value.location.x / totalWidth, 1.0))
                                    trimEnd = newEnd
                                    // Remove split points outside new trim range
                                    splitPoints = splitPoints.filter { $0 > trimStart && $0 < trimEnd }
                                }
                        )

                    // Playhead (white vertical line with circle handle)
                    let clampedPlayhead = max(trimStart, min(playheadPosition, trimEnd))
                    ZStack {
                        // White vertical line
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: geometry.size.height)

                        // Circle handle at top
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .offset(y: -geometry.size.height / 2 + 7)

                        // Circle handle at bottom
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .offset(y: geometry.size.height / 2 - 7)
                    }
                    .position(x: totalWidth * clampedPlayhead, y: geometry.size.height / 2)
                    .gesture(
                        DragGesture(coordinateSpace: .named("timeline"))
                            .onChanged { value in
                                isDraggingPlayhead = true
                                let newPosition = max(trimStart, min(value.location.x / totalWidth, trimEnd))
                                playheadPosition = newPosition
                                onPlayheadDrag?(newPosition)
                            }
                            .onEnded { _ in
                                isDraggingPlayhead = false
                            }
                    )
                }
            }
            .coordinateSpace(name: "timeline")
            .cornerRadius(8)
        }
        .frame(height: 60)
        .onAppear {
            generateThumbnails()
        }
    }

    // Calculate segments from split points
    private var segments: [(start: Double, end: Double)] {
        var result: [(Double, Double)] = []
        var lastPoint = trimStart

        // Get splits that are within trim range, sorted
        let validSplits = splitPoints.filter { $0 > trimStart && $0 < trimEnd }.sorted()

        for split in validSplits {
            result.append((lastPoint, split))
            lastPoint = split
        }
        result.append((lastPoint, trimEnd))

        return result
    }

    @ViewBuilder
    private func handleView(isLeft: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.yellow)
            .frame(width: handleWidth, height: 60)
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 4, height: 20)
            }
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
