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
    let onExport: (Double, Double) -> Void  // trimStart, trimEnd (0-1)

    @State private var trimStart: Double = 0.0
    @State private var trimEnd: Double = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with Cancel and Export
                HStack {
                    Button {
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
                        onExport(trimStart, trimEnd)
                    } label: {
                        Text("Export")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.yellow)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Video preview area
                VideoPlayerView(url: videoURL)
                    .aspectRatio(9/16, contentMode: .fit)
                    .cornerRadius(12)
                    .padding(.horizontal, 40)

                Spacer()

                // Tools row (placeholder for Add Captions button)
                HStack(spacing: 32) {
                    Button {
                        // Add Captions - will be implemented later
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "captions.bubble")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                            Text("Captions")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.vertical, 20)

                // Timeline scrubber
                VideoTimelineScrubber(
                    videoURL: videoURL,
                    trimStart: $trimStart,
                    trimEnd: $trimEnd
                )
                .padding(.horizontal, 16)

                Spacer().frame(height: 30)
            }
        }
    }
}

// MARK: - Simple Video Player View

struct VideoPlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        let player = AVPlayer(url: url)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()

        // Loop the video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }

        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}

    class PlayerUIView: UIView {
        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }
    }
}
