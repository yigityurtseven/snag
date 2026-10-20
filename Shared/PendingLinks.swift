import Foundation

/// A file-per-link inbox. The share extension drops links here and the app
/// picks them up, so neither side ever rewrites a file the other is reading.
nonisolated enum PendingLinks {
    static func enqueue(_ url: URL) throws {
        let file = AppGroup.pendingDirectory.appending(path: "\(Date.now.timeIntervalSince1970)-\(UUID().uuidString).txt")
        try url.absoluteString.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Returns queued links oldest first and removes them from the inbox.
    static func drain() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: AppGroup.pendingDirectory, includingPropertiesForKeys: nil
        )) ?? []

        return files
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { file in
                defer { try? FileManager.default.removeItem(at: file) }
                let text = try? String(contentsOf: file, encoding: .utf8)
                return text.flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
    }
}
