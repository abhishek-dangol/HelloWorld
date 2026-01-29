import SwiftUI
import AVKit

struct CaptionEditorView: View {
    let videoURL: URL
    @Binding var captions: [CaptionSegment]
    var onExport: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Video preview
                VideoPlayer(player: player)
                    .frame(height: 300)
                    .onAppear {
                        player = AVPlayer(url: videoURL)
                    }

                // Caption list
                List {
                    ForEach($captions) { $caption in
                        CaptionRowView(caption: $caption)
                    }
                }
                .listStyle(.plain)

                // Export button
                Button(action: {
                    onExport()
                }) {
                    Text("Export with Captions")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Edit Captions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CaptionRowView: View {
    @Binding var caption: CaptionSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatTime(caption.startTime) + " - " + formatTime(caption.endTime))
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Caption", text: $caption.text)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, milliseconds)
    }
}
