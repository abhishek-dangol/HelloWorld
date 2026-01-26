//
//  RetouchSettingsView.swift
//  CinematiCam
//

import SwiftUI
import UIKit

struct RetouchSettingsView: View {
    @ObservedObject var cameraManager: CameraManager
    @Binding var isPresented: Bool

    @State private var amount: Float = 0.75
    @State private var radius: Float = 7.0
    @State private var brightness: Float = 0.0
    @State private var warmth: Float = 0.0
    @State private var edgeSoftness: Float = 0.3
    @State private var faceExpansion: Float = 0.15
    @State private var selectedPreset: RetouchPreset? = .soft

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Presets
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PRESETS")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                PresetButton(title: "Natural", subtitle: "Subtle", isSelected: selectedPreset == .natural) {
                                    applyPreset(.natural)
                                }
                                PresetButton(title: "Soft", subtitle: "Everyday", isSelected: selectedPreset == .soft) {
                                    applyPreset(.soft)
                                }
                                PresetButton(title: "Glam", subtitle: "Strong", isSelected: selectedPreset == .glam) {
                                    applyPreset(.glam)
                                }
                                PresetButton(title: "Porcelain", subtitle: "Flawless", isSelected: selectedPreset == .porcelain) {
                                    applyPreset(.porcelain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    Divider()
                        .padding(.horizontal)

                    // Sliders
                    VStack(spacing: 20) {
                        SliderRow(
                            icon: "wand.and.rays",
                            title: "Smoothing",
                            value: $amount,
                            range: 0...1,
                            format: "%.0f%%",
                            multiplier: 100
                        ) {
                            selectedPreset = nil
                            cameraManager.setRetouchAmount(amount)
                        }

                        SliderRow(
                            icon: "circle.hexagongrid",
                            title: "Radius",
                            value: $radius,
                            range: 1...15,
                            format: "%.1f",
                            multiplier: 1
                        ) {
                            selectedPreset = nil
                            cameraManager.setRetouchRadius(radius)
                        }

                        SliderRow(
                            icon: "sun.max",
                            title: "Skin Glow",
                            value: $brightness,
                            range: -0.1...0.2,
                            format: "%+.0f%%",
                            multiplier: 100
                        ) {
                            selectedPreset = nil
                            cameraManager.setSkinBrightness(brightness)
                        }

                        SliderRow(
                            icon: "thermometer.sun",
                            title: "Warmth",
                            value: $warmth,
                            range: -0.3...0.3,
                            format: "%+.0f",
                            multiplier: 100
                        ) {
                            selectedPreset = nil
                            cameraManager.setSkinWarmth(warmth)
                        }

                        SliderRow(
                            icon: "circle.dashed",
                            title: "Edge Blend",
                            value: $edgeSoftness,
                            range: 0.1...0.5,
                            format: "%.0f%%",
                            multiplier: 100
                        ) {
                            selectedPreset = nil
                            cameraManager.setEdgeSoftness(edgeSoftness)
                        }

                        SliderRow(
                            icon: "person.crop.rectangle",
                            title: "Face Area",
                            value: $faceExpansion,
                            range: 0...0.4,
                            format: "%.0f%%",
                            multiplier: 100
                        ) {
                            selectedPreset = nil
                            cameraManager.setFaceExpansion(faceExpansion)
                        }
                    }
                    .padding(.horizontal)

                    // Reset button
                    Button {
                        resetToDefaults()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Defaults")
                        }
                        .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .padding(.top, 20)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Retouch Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            loadCurrentValues()
        }
    }

    private func loadCurrentValues() {
        amount = cameraManager.retouchAmount
        radius = cameraManager.retouchRadius
        brightness = cameraManager.skinBrightness
        warmth = cameraManager.skinWarmth
        edgeSoftness = cameraManager.edgeSoftness
        faceExpansion = cameraManager.faceExpansion
    }

    private func applyPreset(_ preset: RetouchPreset) {
        selectedPreset = preset
        cameraManager.applyRetouchPreset(preset)
        loadCurrentValues()
        HapticFeedback.impact()
    }

    private func resetToDefaults() {
        cameraManager.resetRetouchParameters()
        loadCurrentValues()
        selectedPreset = .soft
        HapticFeedback.impact()
    }
}

struct PresetButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            .frame(width: 80, height: 60)
            .background(isSelected ? Color.yellow.opacity(0.2) : Color(UIColor.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 2)
            )
        }
        .foregroundColor(isSelected ? .yellow : .primary)
    }
}

struct SliderRow: View {
    let icon: String
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let format: String
    let multiplier: Float
    let onChange: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.yellow)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Text(String(format: format, value * multiplier))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(width: 50, alignment: .trailing)
            }

            Slider(value: $value, in: range)
                .tint(.yellow)
                .onChange(of: value) { _ in
                    onChange()
                }
        }
    }
}
