import SwiftUI

@main
struct SnagApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var processor = LinkProcessor(store: LibraryStore(), accounts: Accounts())
    @State private var toasts = Toasts()
    #if os(macOS)
    @State private var engine = EngineInstaller()
    #endif

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .toastOverlay()
                .environment(processor)
                .environment(processor.store)
                .environment(processor.accounts)
                .environment(toasts)
                .environment(\.itemActions, ItemActions(store: processor.store, processor: processor, toasts: toasts))
                #if os(macOS)
                .environment(engine)
                .task { await engine.refresh() }
                #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { processor.processPendingLinks() }
        }

        #if os(macOS)
        Settings {
            TabView {
                Tab("Engine", systemImage: "shippingbox") { EngineSettingsView() }
                Tab("Accounts", systemImage: "person.crop.circle") {
                    AccountsView().frame(width: 480, height: 620)
                }
            }
            .environment(engine)
            .environment(processor)
            .environment(processor.accounts)
        }
        #endif
    }
}

#if os(iOS)
import AVFoundation
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Videos are the point of the app: play their sound even when the
        // ring/silent switch is on silent.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        return true
    }

    /// iOS woke the app for finished downloads: the app's own, or ones the
    /// share extension started.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundSessionEvents.store(completionHandler, for: identifier)
        if identifier.hasPrefix(DownloadManager.shareSessionPrefix) {
            LinkProcessor.current?.connectShareSession(identifier)
        }
    }

    /// Tapping a "Downloaded" notification opens the post.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let id = response.notification.request.content.userInfo[DownloadNotifications.itemIDKey] as? String,
              let uuid = UUID(uuidString: id) else { return }
        OpenItemRequest.shared.itemID = uuid
    }
}

/// A post to open in the viewer, from a tapped notification. It may arrive
/// before the library is on screen, so it waits here until it's taken.
@Observable
final class OpenItemRequest {
    static let shared = OpenItemRequest()
    var itemID: UUID?
}
#endif
