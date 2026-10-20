#if os(iOS)
import SwiftUI
import UIKit
import UserNotifications

/// Accounts, notifications, storage, privacy and what Snag is built on.
/// (The Mac has its own Settings window with the same accounts pane.)
struct SettingsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Accounts.self) private var accounts
    @State private var loggingIn: Site?
    @State private var isShowingWelcome = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var mediaSize: Int64?

    var body: some View {
        NavigationStack {
            Form {
                help
                accountsSection
                notifications
                storage
                privacy
                about
            }
            .loginSheet($loggingIn, accounts: accounts)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refresh() }
            // Back from the Settings app, the notification switch may have changed.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refresh() } }
            }
        }
    }

    // MARK: Sections

    private var accountsSection: some View {
        Section {
            AccountRows { loggingIn = $0 }
            NavigationLink {
                Form { LoginSafetyPoints() }
                    .navigationTitle("How Logins Work")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("How logins work", systemImage: "lock.shield")
            }
        } header: {
            Text("Accounts")
        } footer: {
            Text("Optional. Logging in lets Snag download posts only signed-in users can see. Your password never reaches Snag, and your login stays on this iPhone.")
        }
    }

    private var help: some View {
        Section {
            Button {
                isShowingWelcome = true
            } label: {
                Label("How to Use Snag", systemImage: "questionmark.circle")
                    .foregroundStyle(.primary)
            }
            .fullScreenCover(isPresented: $isShowingWelcome) {
                WelcomeView { isShowingWelcome = false }
            }
        }
    }

    private var notifications: some View {
        Section {
            Button {
                openURL(URL(string: UIApplication.openNotificationSettingsURLString)!)
            } label: {
                LabeledContent {
                    Text(notificationStatusText)
                } label: {
                    Label("Download Notifications", systemImage: "bell.badge")
                        .foregroundStyle(.primary)
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("When you share a post to Snag, it downloads in the background and lets you know when it's saved, so you don't have to open the app.")
        }
    }

    private var storage: some View {
        Section("Storage") {
            LabeledContent("Posts", value: store.items.count.formatted())
            LabeledContent("Space Used") {
                if let mediaSize {
                    Text(mediaSize.formatted(.byteCount(style: .file)))
                } else {
                    ProgressView()
                }
            }
        }
    }

    private var privacy: some View {
        Section {
            Label {
                Text("Everything happens on your iPhone. Posts download straight from the site to your phone. Snag has no server, no sign-up and no analytics.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "hand.raised").foregroundStyle(.tint)
            }
        } header: {
            Text("Privacy")
        }
    }

    private var about: some View {
        Section {
            LabeledContent("Version", value: Self.appVersion)
            ForEach(Self.engineVersions, id: \.name) { engine in
                Link(destination: engine.url) {
                    LabeledContent {
                        Text(engine.version)
                    } label: {
                        Text(engine.name).foregroundStyle(.primary)
                    }
                }
            }
        } header: {
            Text("About")
        } footer: {
            Text("Snag downloads with the open-source projects above. It isn't affiliated with or endorsed by Instagram, TikTok or X. Only save posts you have the right to keep.")
        }
    }

    // MARK: Details

    private var notificationStatusText: String {
        switch notificationStatus {
        case .authorized, .ephemeral: "On"
        case .provisional: "Delivered Quietly"
        case .denied: "Off"
        case .notDetermined: "Not Set Up"
        case nil: ""
        @unknown default: ""
        }
    }

    private func refresh() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        mediaSize = await Task.detached(priority: .utility) { Self.size(of: AppGroup.mediaDirectory) }.value
    }

    private nonisolated static func size(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys)
        var total: Int64 = 0
        while let file = files?.nextObject() as? URL {
            let values = try? file.resourceValues(forKeys: Set(keys))
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private struct Engine {
        let name: String
        let version: String
        let url: URL
    }

    /// Read from the packages bundled in the app, so it's always what's really there.
    private static let engineVersions: [Engine] = {
        let packages = Bundle.main.bundleURL.appending(path: "app_packages")
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: packages.path(percentEncoded: false))) ?? []
        func version(of package: String) -> String {
            folders.first { $0.hasPrefix(package + "-") && $0.hasSuffix(".dist-info") }
                .map { String($0.dropFirst(package.count + 1).dropLast(".dist-info".count)) } ?? "—"
        }
        return [
            Engine(name: "yt-dlp", version: version(of: "yt_dlp"), url: URL(string: "https://github.com/yt-dlp/yt-dlp")!),
            Engine(name: "gallery-dl", version: version(of: "gallery_dl"), url: URL(string: "https://github.com/mikf/gallery-dl")!),
        ]
    }()
}
#endif
