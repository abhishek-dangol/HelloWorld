//
//  DisplayLinkController.swift
//  CinematiCam
//
//  Created by Abhishek Dangol on 1/30/26.
//

import Foundation
import QuartzCore
import AVFoundation
import Combine

// Wrapper for use with @StateObject in SwiftUI
final class DisplayLinkControllerWrapper: ObservableObject {
    let controller = DisplayLinkController()
}

final class DisplayLinkController {

    private var displayLink: CADisplayLink?
    private weak var player: AVPlayer?
    private var videoDuration: Double = 0
    private var onPositionUpdate: ((Double) -> Void)?
    private var trimEnd: Double = 1.0
    private var trimStart: Double = 0.0
    private var onPlaybackEnded: (() -> Void)?
    private var splitPoints: [Double] = []
    private var deletedSegments: Set<Int> = []

    deinit {
        stop()
    }

    func configure(
        player: AVPlayer,
        duration: Double,
        trimStart: Double = 0.0,
        trimEnd: Double = 1.0,
        splitPoints: [Double] = [],
        deletedSegments: Set<Int> = [],
        onPositionUpdate: @escaping (Double) -> Void,
        onPlaybackEnded: @escaping () -> Void
    ) {
        self.player = player
        self.videoDuration = duration
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.splitPoints = splitPoints
        self.deletedSegments = deletedSegments
        self.onPositionUpdate = onPositionUpdate
        self.onPlaybackEnded = onPlaybackEnded
    }

    func start() {
        guard displayLink == nil else { return }
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink?.add(to: .main, forMode: .common)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkFired(_ displayLink: CADisplayLink) {
        guard let player = player, videoDuration > 0 else { return }

        let currentTime = CMTimeGetSeconds(player.currentTime())
        let position = currentTime / videoDuration

        // Check if in a deleted segment
        let currentSegment = getSegmentIndex(for: position)
        if deletedSegments.contains(currentSegment) {
            // Seek to next non-deleted segment
            if let nextStart = findNextNonDeletedSegmentStart(after: position) {
                let seekTime = CMTime(seconds: nextStart * videoDuration, preferredTimescale: 600)
                player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
                return // Skip this frame update
            } else {
                // No more non-deleted segments, end playback
                onPlaybackEnded?()
                return
            }
        }

        // Direct update - NO animation
        onPositionUpdate?(position)

        if position >= trimEnd {
            onPlaybackEnded?()
        }
    }

    // Get which segment a position belongs to
    private func getSegmentIndex(for position: Double) -> Int {
        let sorted = splitPoints.sorted()
        for (index, split) in sorted.enumerated() {
            if position < split {
                return index
            }
        }
        return sorted.count
    }

    // Find the start of the next non-deleted segment after the given position
    private func findNextNonDeletedSegmentStart(after position: Double) -> Double? {
        let sorted = splitPoints.sorted()
        var boundaries = [0.0] + sorted + [1.0]

        for i in 0..<(boundaries.count - 1) {
            let segStart = boundaries[i]
            if segStart > position && !deletedSegments.contains(i) {
                return segStart
            }
        }
        return nil // No more non-deleted segments
    }
}
