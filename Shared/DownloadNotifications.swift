#if os(iOS)
import Foundation
import UserNotifications

/// "Downloaded" notifications for posts shared to Snag while the app wasn't
/// open, since only the open app can show a Live Activity.
nonisolated enum DownloadNotifications {
    static let itemIDKey = "itemID"

    /// From the share extension: quiet delivery to Notification Center needs
    /// no prompt, so it works before the app has ever asked.
    static func requestProvisional() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .provisional])
    }

    /// From the app: asks properly, which also upgrades a provisional grant.
    static func requestAuthorization() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .notDetermined || status == .provisional else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func post(for item: MediaItem) {
        let content = UNMutableNotificationContent()
        let source = item.uploader ?? item.site.displayName
        switch item.status {
        case .done:
            let count = item.files.count
            content.title = "Downloaded"
            content.body = count > 1 ? "\(count) items from \(source)" : "From \(source)"
            if let attachment = attachment(for: item) { content.attachments = [attachment] }
        case .failed(let message):
            content.title = "Couldn't download"
            content.body = "\(source): \(message)"
        default:
            return
        }
        content.sound = .default
        content.threadIdentifier = "downloads"
        content.userInfo = [itemIDKey: item.id.uuidString]
        let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// The first photo as a thumbnail. iOS moves an attachment's file into its
    /// own store, so it gets a copy.
    private static func attachment(for item: MediaItem) -> UNNotificationAttachment? {
        guard let file = item.files.first(where: { $0.kind == .image }) ?? item.files.first,
              let url = file.localURL else { return nil }
        let copy = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).\(url.pathExtension)")
        guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: file.id.uuidString, url: copy)
    }
}
#endif
