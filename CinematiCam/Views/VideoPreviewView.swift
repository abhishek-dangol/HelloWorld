//
//  VideoPreviewView.swift
//  CinematiCam
//
//  Created by Abhishek Dangol on 1/29/26.
//

import SwiftUI
import AVFoundation
import Combine

struct VideoPreviewView: View {
    let videoURL: URL
    let onDiscard: () -> Void
    let onEdit: () -> Void
    let onSave: () -> Void

    @StateObject private var playerManager = LoopingPlayerManager()

    var body: some View {
        ZStack {
            // Black background
            Color.black.ignoresSafeArea()

            // Looping video player
            LoopingVideoPlayer(player: playerManager.player)
                .ignoresSafeArea()
        }
        // Discard button (top-left)
        .overlay(alignment: .topLeading) {
            Button {
                onDiscard()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(14)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .padding(.leading, 20)
            .padding(.top, 60)
        }
        // Bottom controls (Edit + Save)
        .overlay(alignment: .bottom) {
            HStack(spacing: 40) {
                // Edit button (scissors)
                Button {
                    onEdit()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "scissors")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                        Text("Edit")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                    }
                }

                // Save button (checkmark)
                Button {
                    onSave()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.red)
                            .clipShape(Circle())
                        Text("Save")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.bottom, 50)
        }
        .onAppear {
            playerManager.play(url: videoURL)
        }
        .onDisappear {
            playerManager.stop()
        }
    }
}

// MARK: - Looping Player Manager

@MainActor
class LoopingPlayerManager: ObservableObject {
    @Published private(set) var player: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?

    func play(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        player = queuePlayer
        queuePlayer.play()
    }

    func stop() {
        player?.pause()
        player = nil
        playerLooper = nil
    }
}

// MARK: - Looping Video Player View

struct LoopingVideoPlayer: UIViewRepresentable {
    let player: AVQueuePlayer?

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    class PlayerView: UIView {
        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }
    }
}
