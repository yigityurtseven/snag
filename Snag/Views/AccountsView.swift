import SwiftUI
import WebKit

/// One row per site: its logo, whether you're logged in, and the button to
/// change that. The login sheet belongs to the screen around it (see
/// `loginSheet`): in a Form, modifiers on these rows would be copied onto
/// every row, and three sheets on one binding close each other.
struct AccountRows: View {
    @Environment(Accounts.self) private var accounts
    let logIn: (Site) -> Void

    var body: some View {
        ForEach(Accounts.supported, id: \.self) { site in
            let isLoggedIn = accounts.loggedIn.contains(site)
            HStack(spacing: 12) {
                SiteBadge(site: site, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(site.displayName)
                    Text(isLoggedIn ? "Logged in" : "Not logged in")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoggedIn {
                    Button("Log Out", role: .destructive) { Task { await accounts.logOut(site) } }
                        .buttonStyle(.borderless)
                } else {
                    Button("Log In") { logIn(site) }
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

extension View {
    /// Presents the login page for `site`, and refreshes who's logged in.
    func loginSheet(_ site: Binding<Site?>, accounts: Accounts) -> some View {
        sheet(item: site) { site in
            LoginSheet(site: site)
        }
        .task { await accounts.refresh() }
    }
}

/// What happens to a login in Snag, in plain words. Every point here is
/// something the code actually does (see `Accounts`), so keep them in step.
struct LoginSafetyPoints: View {
    private struct Point: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    #if os(iOS)
    private static let device = "iPhone"
    #else
    private static let device = "Mac"
    #endif

    private let points = [
        Point(symbol: "person.crop.circle.badge.questionmark", title: "Only when you need it",
              detail: "Public posts download without logging in. A login only helps with posts a site hides from visitors, like some Instagram carousels, age-restricted TikToks or protected posts on X."),
        Point(symbol: "key", title: "Your password never reaches Snag",
              detail: "You sign in on the site's own page, in a browser inside Snag. Snag doesn't read or save anything you type there."),
        Point(symbol: "lock", title: "It stays on this \(device)",
              detail: "After you sign in, the site gives Snag's browser a login cookie, the same way it would give one to Safari. Snag keeps it on this \(device) in storage only Snag and its share extension can open, and never syncs it."),
        Point(symbol: "arrow.up.right", title: "Sent only to that site",
              detail: "The cookie only goes back to the site it came from, Instagram's to Instagram and so on, when you download a post from it. Snag has no server in between."),
        Point(symbol: "eye", title: "Snag only looks",
              detail: "Your login is used to view posts, nothing more. Snag never posts, likes, follows or sends messages."),
        Point(symbol: "rectangle.portrait.and.arrow.right", title: "Log out anytime",
              detail: "Log Out deletes Snag's cookie and website data for that site. To end the session everywhere, also remove it in the site's own security settings."),
        Point(symbol: "exclamationmark.triangle", title: "A heads-up",
              detail: "Sites may ask you to verify your account if you download a lot in a short time. If that worries you, log in with a secondary account."),
    ]

    var body: some View {
        ForEach(points) { point in
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(point.title).font(.subheadline.weight(.semibold))
                    Text(point.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: point.symbol).foregroundStyle(.tint)
            }
            .padding(.vertical, 2)
        }
    }
}

/// The Mac's Accounts settings tab.
struct AccountsView: View {
    @Environment(Accounts.self) private var accounts
    @State private var loggingIn: Site?

    var body: some View {
        Form {
            Section {
                AccountRows { loggingIn = $0 }
            } footer: {
                Text("Optional. Logging in lets Snag download posts that are only visible to signed-in users.")
            }
            Section("How Logins Work") {
                LoginSafetyPoints()
            }
        }
        .formStyle(.grouped)
        .loginSheet($loggingIn, accounts: accounts)
    }
}

/// A web view on the site's login page. Closes itself once the session
/// cookie appears, which also covers single-page logins like X's.
struct LoginSheet: View {
    let site: Site
    var onLoggedIn: () -> Void = {}

    @Environment(Accounts.self) private var accounts
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let url = site.loginURL {
                    LoginWebView(url: url, dataStore: accounts.dataStore)
                }
            }
            .navigationTitle("Log in to \(site.displayName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .ignoresSafeArea(edges: .bottom)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 640)
        #endif
        .task {
            while !Task.isCancelled {
                await accounts.refresh()
                if accounts.loggedIn.contains(site) {
                    onLoggedIn()
                    dismiss()
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

extension Site: Identifiable {
    var id: String { rawValue }
}

private struct LoginWebView {
    let url: URL
    let dataStore: WKWebsiteDataStore

    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        // Without the Safari suffix some sites serve a degraded or blocked login page.
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.load(URLRequest(url: url))
        return webView
    }
}

#if os(macOS)
extension LoginWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView() }
    func updateNSView(_ webView: WKWebView, context: Context) {}
}
#else
extension LoginWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView() }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}
#endif
