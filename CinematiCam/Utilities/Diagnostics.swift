import Foundation
import UIKit

/// The diagnostics log shown in Settings › Diagnostics. For our own testing only: set `isOn`
/// to false before the app is released, and the page is gone and nothing is written.
///
/// Add a line from anywhere with `Diagnostics.log("Photo", "what happened")`. The newest lines
/// are kept in a small file, so they are still there after the app is closed and opened again.
enum Diagnostics {
    static let isOn = true

    /// How many lines are kept; older ones drop off
    private static let keep = 400
    private static let queue = DispatchQueue(label: "com.cinematicam.diagnostics", qos: .utility)
    private static let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("diagnostics.log")
    private static var lines: [String] = {
        guard isOn, let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }()
    /// The time on the phone's own clock, to the thousandth of a second
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm:ss.SSS a"
        return formatter
    }()

    static func log(_ area: String, _ text: String) {
        guard isOn else { return }
        let now = Date()
        queue.async {
            let line = "\(stamp.string(from: now))  [\(area)] \(text)"
            print(line)
            lines.append(line)
            if lines.count > keep { lines.removeFirst(lines.count - keep) }
            try? Data(lines.joined(separator: "\n").utf8).write(to: file, options: .atomic)
        }
    }

    /// Oldest first
    static func allLines() -> [String] {
        queue.sync { lines }
    }

    static func clear() {
        queue.sync {
            lines = []
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// One line at launch: which build this is and what it runs on
    static func logStart() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        log("App", "Opened. Version \(version) (\(build)), \(model), iOS \(UIDevice.current.systemVersion)")
    }
}
