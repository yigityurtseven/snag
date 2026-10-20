#if os(iOS)
import ActivityKit
import Foundation

/// The Live Activity (Lock Screen and Dynamic Island) for one post while it
/// downloads. Shared by the app, which drives it, and the widget extension,
/// which draws it.
nonisolated struct DownloadActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable {
            case finding, downloading, done, failed
        }

        var phase: Phase
        var uploader: String?
        var fileCount: Int = 0
        /// 0...1 across all of the post's files.
        var progress: Double = 0
    }

    var itemID: UUID
    var site: Site
}

extension DownloadActivityAttributes {
    /// Opens the post in Snag when the activity is tapped.
    static func url(for itemID: UUID) -> URL {
        URL(string: "snag://item/\(itemID.uuidString)")!
    }
}
#endif
