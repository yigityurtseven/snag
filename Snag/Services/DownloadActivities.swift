import Foundation
#if os(iOS)
import ActivityKit
import UIKit
#endif

/// Shows each post's download as a Live Activity, so you can follow it in the
/// Dynamic Island or on the Lock Screen after leaving the app, and get a nudge
/// when it's done. Does nothing on the Mac.
final class DownloadActivities {
    #if os(iOS)
    private var fileProgress: [MediaFile.ID: Double] = [:]
    private var lastSent: [MediaItem.ID: Date] = [:]
    #endif

    /// Records how far one file has got. Updates are throttled, since the
    /// downloader reports many times a second.
    func progress(_ fraction: Double, file: MediaFile.ID, in item: MediaItem) {
        #if os(iOS)
        fileProgress[file] = fraction
        update(item)
        #endif
    }

    /// Starts, updates or ends the item's activity to match its status.
    func update(_ item: MediaItem) {
        #if os(iOS)
        let state = state(for: item)
        let finished = state.phase == .done || state.phase == .failed

        guard let activity = activity(for: item.id) else {
            // Activities can only start while the app is in the foreground,
            // which is where processing starts.
            guard !finished, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let attributes = DownloadActivityAttributes(itemID: item.id, site: item.site)
            _ = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
            lastSent[item.id] = .now
            return
        }

        let alreadyShown = activity.content.state == state
        if !finished {
            guard !alreadyShown else { return }
            if activity.content.state.phase == state.phase,
               let last = lastSent[item.id], Date.now.timeIntervalSince(last) < 1 {
                return
            }
        }
        lastSent[item.id] = .now

        let content = ActivityContent(state: state, staleDate: nil)
        let finishWork = beginBackgroundWork()
        Task {
            defer { finishWork() }
            guard finished else {
                await activity.update(content)
                return
            }
            for file in item.files { fileProgress[file.id] = nil }
            lastSent[item.id] = nil
            // Watching the app already, or told before: just go.
            if alreadyShown || UIApplication.shared.applicationState == .active {
                await activity.end(content, dismissalPolicy: .immediate)
                return
            }
            // Pops the island open (and lights up the Lock Screen) to say it's done,
            // then stays on the Lock Screen a few minutes. Opening Snag clears it.
            let alert = AlertConfiguration(
                title: state.phase == .done ? "Downloaded" : "Couldn't download",
                body: "\(item.uploader ?? item.site.displayName)",
                sound: .default
            )
            await activity.update(content, alertConfiguration: alert)
            try? await Task.sleep(for: .seconds(4))
            await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(5 * 60)))
        }
        #endif
    }

    /// Run when the app comes to the front. Downloads still going keep their
    /// activity; everything else goes, including finished ones lingering on
    /// the Lock Screen, since the result is right there in the app now. Also
    /// catches activities left behind by a run that was quit or suspended
    /// before it could end them.
    func reconcile(with store: LibraryStore) {
        #if os(iOS)
        for activity in Activity<DownloadActivityAttributes>.activities {
            let item = store.item(activity.attributes.itemID)
            let inProgress = item.map { $0.status == .extracting || $0.status == .downloading } ?? false
            if let item, inProgress, activity.activityState == .active {
                update(item)
            } else {
                Task { await activity.end(activity.content, dismissalPolicy: .immediate) }
            }
        }
        #endif
    }

    #if os(iOS)
    private func activity(for id: MediaItem.ID) -> Activity<DownloadActivityAttributes>? {
        Activity<DownloadActivityAttributes>.activities.first {
            $0.attributes.itemID == id && $0.activityState == .active
        }
    }

    private func state(for item: MediaItem) -> DownloadActivityAttributes.ContentState {
        var state = DownloadActivityAttributes.ContentState(phase: .finding, uploader: item.uploader, fileCount: item.files.count)
        switch item.status {
        case .extracting:
            state.phase = .finding
        case .downloading:
            state.phase = .downloading
            let done = item.files.reduce(0.0) { total, file in
                total + (file.localFilename != nil ? 1 : fileProgress[file.id] ?? 0)
            }
            // Rounded, so tiny byte counts don't count as changes.
            state.progress = item.files.isEmpty ? 0 : (done / Double(item.files.count) * 50).rounded() / 50
        case .done:
            state.phase = .done
            state.progress = 1
        case .failed:
            state.phase = .failed
        }
        return state
    }

    /// The app may be suspended right after a background download finishes;
    /// ask for the moment it takes to tell the activity.
    private func beginBackgroundWork() -> () -> Void {
        let application = UIApplication.shared
        var task = UIBackgroundTaskIdentifier.invalid
        task = application.beginBackgroundTask(withName: "Update Live Activity") {
            application.endBackgroundTask(task)
            task = .invalid
        }
        return {
            if task != .invalid { application.endBackgroundTask(task) }
        }
    }
    #endif
}
