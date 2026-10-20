import Foundation

/// Starts a shared post downloading straight from the share sheet, so it's
/// saved without opening Snag: finds the media with the app's engine, hands
/// the post to the app's inbox, and queues the files in a background session.
/// iOS finishes the downloads after the extension is gone and wakes the app
/// to file them.
@MainActor
enum ShareDownloader {
    /// Files still downloading while the extension is alive, per post.
    private static var remaining: [MediaItem.ID: Set<MediaFile.ID>] = [:]
    private static var items: [MediaItem.ID: MediaItem] = [:]
    private static var sessions: [DownloadManager] = []

    /// Returns the post if its downloads started, or nil to leave the link
    /// for the app (no engine, a login wall, a timeout…).
    static func start(_ url: URL) async -> MediaItem? {
        guard let result = await extract(url), let media = result.media, !media.isEmpty else { return nil }

        var item = MediaItem(sourceURL: url)
        item.title = result.title
        item.uploader = result.uploader
        item.status = .downloading
        item.files = media.map { MediaFile(kind: $0.kind, remoteURL: $0.url, headers: $0.headers, fileExtension: $0.ext) }
        item.downloadSession = DownloadManager.shareSessionIdentifier(for: item.id)

        // In the inbox before any file can finish, so the app always knows the post.
        do { try ShareInbox.add(item) } catch { return nil }

        items[item.id] = item
        remaining[item.id] = Set(item.files.map(\.id))
        let session = DownloadManager(identifier: item.downloadSession!) { itemID, fileID, filename, error in
            let finished = ShareInbox.FinishedFile(item: itemID, file: fileID, filename: filename, error: error)
            ShareInbox.recordFinished(finished)
            Task { @MainActor in fileFinished(finished) }
        }
        sessions.append(session)
        for file in item.files { session.enqueue(file, for: item.id) }

        await DownloadNotifications.requestProvisional()
        return item
    }

    /// Runs the engine, giving up after a while: past that, opening the app is the better bet.
    private static func extract(_ url: URL) async -> ExtractionResult? {
        let cookies = FileManager.default.fileExists(atPath: AppGroup.cookiesFile.path(percentEncoded: false))
            ? AppGroup.cookiesFile : nil
        return await withTaskGroup(of: ExtractionResult?.self) { group in
            group.addTask { try? await EmbeddedPythonExtractor().extract(url, cookiesFile: cookies) }
            group.addTask {
                try? await Task.sleep(for: .seconds(25))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Small posts can finish while the card is still up; if every file does,
    /// the notification comes from here (otherwise the app sends it).
    private static func fileFinished(_ finished: ShareInbox.FinishedFile) {
        guard var item = items[finished.item], var files = remaining[finished.item] else { return }
        if let index = item.files.firstIndex(where: { $0.id == finished.file }) {
            item.files[index].localFilename = finished.filename
        }
        if let error = finished.error { item.status = .failed(error) }
        files.remove(finished.file)
        items[item.id] = item
        remaining[item.id] = files
        guard files.isEmpty else { return }
        if item.status == .downloading { item.status = .done }
        DownloadNotifications.post(for: item)
    }
}
