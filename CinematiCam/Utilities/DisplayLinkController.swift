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

    deinit {
        stop()
    }

    func configure(
        player: AVPlayer,
        duration: Double,
        trimStart: Double = 0.0,
        trimEnd: Double = 1.0,
        onPositionUpdate: @escaping (Double) -> Void,
        onPlaybackEnded: @escaping () -> Void
    ) {
        self.player = player
        self.videoDuration = duration
        self.trimStart = trimStart
        self.trimEnd = trimEnd
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

        // Direct update - NO animation
        onPositionUpdate?(position)

        if position >= trimEnd {
            onPlaybackEnded?()
        }
    }
}
