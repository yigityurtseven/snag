import Foundation

/// Downloads media with a background URLSession, so the system finishes
/// transfers even after the app is suspended or quit. The app has one session;
/// each share extension run starts its own, which the app takes over when iOS
/// wakes it for the finished files (only one process can use a session).
nonisolated final class DownloadManager: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let sessionIdentifier = "com.yigityurtseven.Snag.downloads"
    static let shareSessionPrefix = "com.yigityurtseven.Snag.share."

    static func shareSessionIdentifier(for item: MediaItem.ID) -> String {
        shareSessionPrefix + item.uuidString
    }

    let identifier: String

    /// (item, file, saved file name or nil, error message or nil)
    typealias Completion = @Sendable (MediaItem.ID, MediaFile.ID, String?, String?) -> Void
    /// (item, file, fraction downloaded)
    typealias Progress = @Sendable (MediaItem.ID, MediaFile.ID, Double) -> Void

    private let onComplete: Completion
    private let onProgress: Progress?
    private var session: URLSession!

    init(identifier: String = sessionIdentifier, onProgress: Progress? = nil, onComplete: @escaping Completion) {
        self.identifier = identifier
        self.onProgress = onProgress
        self.onComplete = onComplete
        super.init()

        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        #if os(iOS)
        configuration.sharedContainerIdentifier = AppGroup.identifier
        #endif
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        // Recreating the session with the same identifier reconnects to
        // transfers that finished while the app wasn't running.
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func enqueue(_ file: MediaFile, for item: MediaItem.ID) {
        var request = URLRequest(url: file.remoteURL)
        for (field, value) in file.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let task = session.downloadTask(with: request)
        // Stored on the task so it survives an app relaunch.
        task.taskDescription = TaskTag(item: item, file: file.id, ext: file.fileExtension).encoded
        task.resume()
    }

    /// Lets running transfers finish, then lets go of the session so another
    /// process could use its identifier.
    func finishAndInvalidate() {
        session.finishTasksAndInvalidate()
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let tag = TaskTag(downloadTask.taskDescription) else { return }

        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            onComplete(tag.item, tag.file, nil, "Server returned HTTP \(http.statusCode)")
            return
        }

        // `location` is deleted when this method returns, so move it now.
        let filename = "\(tag.file.uuidString).\(tag.ext)"
        let destination = AppGroup.mediaDirectory.appending(path: filename)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            onComplete(tag.item, tag.file, filename, nil)
        } catch {
            onComplete(tag.item, tag.file, nil, error.localizedDescription)
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let onProgress, totalBytesExpectedToWrite > 0, let tag = TaskTag(downloadTask.taskDescription) else { return }
        onProgress(tag.item, tag.file, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let tag = TaskTag(task.taskDescription) else { return }
        onComplete(tag.item, tag.file, nil, error.localizedDescription)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = BackgroundSessionEvents.takeHandler(for: identifier)
        // The delegate's completion calls hop to the main actor; let them land first.
        DispatchQueue.main.async { handler?() }
    }
}

private nonisolated struct TaskTag {
    var item: UUID
    var file: UUID
    var ext: String

    init(item: UUID, file: UUID, ext: String) {
        self.item = item
        self.file = file
        self.ext = ext
    }

    init?(_ string: String?) {
        let parts = string?.split(separator: "|").map(String.init) ?? []
        guard parts.count == 3, let item = UUID(uuidString: parts[0]), let file = UUID(uuidString: parts[1]) else {
            return nil
        }
        self.init(item: item, file: file, ext: parts[2])
    }

    var encoded: String { "\(item.uuidString)|\(file.uuidString)|\(ext)" }
}

/// The completion handlers iOS gives the app when it wakes it for finished
/// background downloads. The app delegate stores them; the matching session
/// calls one once it has handled every event.
nonisolated enum BackgroundSessionEvents {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: () -> Void] = [:]

    static func store(_ handler: @escaping () -> Void, for identifier: String) {
        lock.withLock { handlers[identifier] = handler }
    }

    static func takeHandler(for identifier: String) -> (() -> Void)? {
        lock.withLock { handlers.removeValue(forKey: identifier) }
    }
}
