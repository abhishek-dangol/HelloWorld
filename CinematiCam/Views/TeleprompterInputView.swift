import SwiftUI

struct TeleprompterInputView: View {
    @Binding var scriptText: String
    @Binding var scrollSpeed: Int
    @Binding var isEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextEditor(text: $scriptText)
                    .font(.body)
                    .padding(8)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(10)
                    .frame(minHeight: 200)

                // Speed picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scroll Speed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("Speed", selection: $scrollSpeed) {
                        ForEach(1...5, id: \.self) { speed in
                            Text("\(speed)x").tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Word count + estimated time
                HStack {
                    let words = scriptText.split(separator: " ").count
                    let estimatedSeconds = max(0, Double(words) / (Double(scrollSpeed) * 1.5))
                    Text("\(words) words")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("~\(Int(estimatedSeconds))s at \(scrollSpeed)x")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Clear button
                if !scriptText.isEmpty {
                    Button(role: .destructive) {
                        scriptText = ""
                    } label: {
                        Label("Clear Script", systemImage: "trash")
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Teleprompter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isEnabled = !scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        dismiss()
                    }
                }
            }
        }
    }
}
