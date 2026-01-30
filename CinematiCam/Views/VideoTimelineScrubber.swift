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

    @State private var thumbnails: [UIImage] = []
    @State private var isLoading = true

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

                    // Trim selection border
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.yellow, lineWidth: 3)
                        .frame(width: totalWidth * (trimEnd - trimStart))
                        .position(x: totalWidth * (trimStart + trimEnd) / 2, y: geometry.size.height / 2)

                    // Left handle
                    handleView(isLeft: true)
                        .position(x: totalWidth * trimStart, y: geometry.size.height / 2)
                        .gesture(
                            DragGesture(coordinateSpace: .named("timeline"))
                                .onChanged { value in
                                    let newStart = max(0, min(value.location.x / totalWidth, trimEnd - 0.1))
                                    trimStart = newStart
                                }
                        )

                    // Right handle
                    handleView(isLeft: false)
                        .position(x: totalWidth * trimEnd, y: geometry.size.height / 2)
                        .gesture(
                            DragGesture(coordinateSpace: .named("timeline"))
                                .onChanged { value in
                                    let newEnd = max(trimStart + 0.1, min(value.location.x / totalWidth, 1.0))
                                    trimEnd = newEnd
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
