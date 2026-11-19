import SwiftUI

/// Settings › Diagnostics: the log of what the app did, newest line first. For our own
/// testing only (see `Diagnostics.isOn`).
struct DiagnosticsView: View {
    @State private var lines: [String] = []

    var body: some View {
        List {
            Section {
                if lines.isEmpty {
                    Text("Nothing yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(lines.reversed().enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("Log, newest first")
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Clear") {
                    Diagnostics.clear()
                    lines = []
                }
                .disabled(lines.isEmpty)
            }
        }
        .onAppear { lines = Diagnostics.allLines() }
    }
}
