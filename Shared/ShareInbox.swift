import Foundation

/// How the share extension hands over posts it started downloading itself.
/// Like `PendingLinks`, it's a file per entry, so the extension never writes
/// to the library the app owns.
nonisolated enum ShareInbox {
    /// One file finishing (or failing), seen by the extension before it quit.
    struct FinishedFile: Codable, Sendable {
        var item: MediaItem.ID
        var file: MediaFile.ID
        var filename: String?
        var error: String?
    }

    static func add(_ item: MediaItem) throws {
        let data = try JSONEncoder().encode(item)
        try data.write(to: AppGroup.sharedItemsDirectory.appending(path: "\(item.id.uuidString).json"), options: .atomic)
    }

    static func recordFinished(_ finished: FinishedFile) {
        guard let data = try? JSONEncoder().encode(finished) else { return }
        try? data.write(to: AppGroup.finishedFilesDirectory.appending(path: "\(finished.file.uuidString).json"), options: .atomic)
    }

    /// Posts handed over, oldest first, removed from the inbox.
    static func drainItems() -> [MediaItem] {
        drain(AppGroup.sharedItemsDirectory, as: MediaItem.self).sorted { $0.createdAt < $1.createdAt }
    }

    static func drainFinished() -> [FinishedFile] {
        drain(AppGroup.finishedFilesDirectory, as: FinishedFile.self)
    }

    private static func drain<T: Decodable>(_ directory: URL, as type: T.Type) -> [T] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            defer { try? FileManager.default.removeItem(at: file) }
            return (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
        }
    }
}
