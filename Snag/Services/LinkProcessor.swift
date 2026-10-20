import Foundation
#if canImport(UIKit)
import UIKit
import UserNotifications
#endif

/// Turns a shared link into a library item: extract media URLs, then hand
/// each file to the background downloader. Also takes over posts the share
/// extension started downloading by itself.
@Observable
final class LinkProcessor {
    let store: LibraryStore
    let accounts: Accounts
    private let extractor: any MediaExtractor
    @ObservationIgnored private var downloads: DownloadManager!
    @ObservationIgnored private let activities = DownloadActivities()
    /// The share extension's background sessions, taken over by the app.
    @ObservationIgnored private var shareSessions: [String: DownloadManager] = [:]

    /// For the app delegate, which iOS calls when it wakes the app for a session.
    static weak var current: LinkProcessor?

    init(store: LibraryStore, accounts: Accounts, extractor: any MediaExtractor = Extractors.platformDefault()) {
        self.store = store
        self.accounts = accounts
        self.extractor = extractor
        self.downloads = DownloadManager { [store, activities] itemID, fileID, fraction in
            Task { @MainActor in
                if let item = store.item(itemID) { activities.progress(fraction, file: fileID, in: item) }
            }
        } onComplete: { [store, activities] itemID, fileID, filename, error in
            Task { @MainActor in
                store.finishFile(item: itemID, file: fileID, filename: filename, error: error)
                if let item = store.item(itemID) { activities.update(item) }
            }
        }
        // Before any session reports a file, so the posts they belong to are known.
        ingestSharedDownloads()
        Self.current = self
    }

    /// Picks up links the share extension queued while the app wasn't running.
    func processPendingLinks() {
        ingestSharedDownloads()
        activities.reconcile(with: store)
        #if os(iOS)
        // Their posts are in the library now; don't leave them piling up.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        #endif
        for url in PendingLinks.drain() {
            submit(url)
        }
        askForNotificationsOnce()
    }

    // MARK: Downloads started by the share extension

    /// Brings in posts the share extension handed over and files that
    /// finished while it was still running.
    func ingestSharedDownloads() {
        for item in ShareInbox.drainItems() where store.item(item.id) == nil {
            store.insert(item)
        }
        for finished in ShareInbox.drainFinished() {
            apply(finished, fromSession: false)
        }
        // A backstop for downloads iOS hasn't woken us for. Fresh ones are left
        // alone: the extension may still be using its session.
        for item in store.items where item.status == .downloading && item.createdAt.timeIntervalSinceNow < -30 {
            if let identifier = item.downloadSession { connectShareSession(identifier) }
        }
    }

    /// Reconnects to a share extension session so its finished files land here.
    func connectShareSession(_ identifier: String) {
        guard shareSessions[identifier] == nil else { return }
        shareSessions[identifier] = DownloadManager(identifier: identifier) { itemID, fileID, filename, error in
            Task { @MainActor in
                guard let processor = LinkProcessor.current else { return }
                processor.ingestSharedDownloads()
                processor.apply(.init(item: itemID, file: fileID, filename: filename, error: error), fromSession: true)
            }
        }
    }

    private func apply(_ finished: ShareInbox.FinishedFile, fromSession: Bool) {
        let wasDownloading = store.item(finished.item)?.status == .downloading
        store.finishFile(item: finished.item, file: finished.file, filename: finished.filename, error: finished.error)
        guard let item = store.item(finished.item), wasDownloading, item.status != .downloading else { return }

        if let identifier = item.downloadSession {
            shareSessions.removeValue(forKey: identifier)?.finishAndInvalidate()
        }
        #if os(iOS)
        // The extension already told the user about files it saw finish itself.
        if fromSession, UIApplication.shared.applicationState != .active {
            DownloadNotifications.post(for: item)
        }
        #endif
    }

    /// Asked once, after the first post, rather than on first launch.
    private func askForNotificationsOnce() {
        #if os(iOS)
        let key = "askedForNotifications"
        guard !store.items.isEmpty, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        Task { await DownloadNotifications.requestAuthorization() }
        #endif
    }

    func submit(_ url: URL) {
        let item = MediaItem(sourceURL: url)
        store.insert(item)
        activities.update(item)
        Task { await process(item) }
    }

    func retry(_ id: MediaItem.ID) {
        guard store.item(id) != nil else { return }
        store.update(id) {
            $0.status = .extracting
            $0.files = []
        }
        guard let item = store.item(id) else { return }
        activities.update(item)
        Task { await process(item) }
    }

    /// Retries every failed item, e.g. after the engine was installed.
    func retryFailed() {
        for item in store.items {
            if case .failed = item.status { retry(item.id) }
        }
    }

    private func process(_ item: MediaItem) async {
        let finishBackgroundWork = beginBackgroundWork()
        defer { finishBackgroundWork() }

        do {
            let result = try await extractor.extract(item.sourceURL, cookiesFile: await accounts.exportCookies())
            let files = (result.media ?? []).map {
                MediaFile(kind: $0.kind, remoteURL: $0.url, headers: $0.headers, fileExtension: $0.ext)
            }
            store.update(item.id) {
                $0.title = result.title
                $0.uploader = result.uploader
                $0.files = files
                $0.status = .downloading
            }
            for file in files {
                downloads.enqueue(file, for: item.id)
            }
        } catch {
            store.update(item.id) { $0.status = .failed(error.localizedDescription) }
        }
        if let item = store.item(item.id) { activities.update(item) }
    }

    /// Extraction takes a few seconds; ask iOS for time to finish it if the
    /// user leaves the app. Downloads themselves don't need this.
    private func beginBackgroundWork() -> () -> Void {
        #if os(iOS)
        let application = UIApplication.shared
        var task = UIBackgroundTaskIdentifier.invalid
        task = application.beginBackgroundTask(withName: "Extract media") {
            application.endBackgroundTask(task)
            task = .invalid
        }
        return {
            if task != .invalid { application.endBackgroundTask(task) }
        }
        #else
        return {}
        #endif
    }
}
