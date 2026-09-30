import Foundation

// MARK: - Debug log for diagnosing launch issues on user machines.
// Appends timestamped lines to /tmp/SlideWand.log. Cheap, no-ops silently on failure.

enum Log {
    static let url = FileManager.default.temporaryDirectory.appendingPathComponent("SlideWand.log")

    static func line(_ s: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        guard let data = ("[\(ts)] \(s)\n").data(using: .utf8) else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let h = try FileHandle(forWritingTo: url)
                h.seekToEndOfFile()
                h.write(data)
                try h.close()
            } else {
                try data.write(to: url)
            }
        } catch {
            // Logging must never break the app.
        }
    }

    static func reset() {
        try? FileManager.default.removeItem(at: url)
    }
}
