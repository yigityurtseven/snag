import Foundation
import Observation
import WebKit

/// Logins made in Snag's web view. Some posts (Instagram carousels,
/// age-restricted TikToks, protected tweets) are only visible to logged-in
/// users, so the session cookies are handed to yt-dlp and gallery-dl.
@Observable
final class Accounts {
    static let supported: [Site] = [.instagram, .tiktok, .x]

    private(set) var loggedIn: Set<Site> = []
    let dataStore = WKWebsiteDataStore.default()

    private static var cookiesFile: URL { AppGroup.cookiesFile }

    init() {
        Task { await refresh() }
    }

    func refresh() async {
        let cookies = await dataStore.httpCookieStore.allCookies()
        let sites = Set(Self.supported.filter { site in cookies.contains(where: site.isSessionCookie) })
        if sites != loggedIn { loggedIn = sites }
        // Keep the shared copy current, since the share extension can't read the web view's cookies.
        _ = await exportCookies()
    }

    func logOut(_ site: Site) async {
        let cookieStore = dataStore.httpCookieStore
        for cookie in await cookieStore.allCookies() where site.owns(cookie) {
            await cookieStore.deleteCookie(cookie)
        }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types).filter { site.owns(domain: $0.displayName) }
        await dataStore.removeData(ofTypes: types, for: records)
        await refresh()
    }

    /// Writes current cookies for the supported sites to a Netscape
    /// cookies.txt (the format both tools read). Returns nil if there are none.
    func exportCookies() async -> URL? {
        let cookies = await dataStore.httpCookieStore.allCookies().filter { cookie in
            Self.supported.contains { $0.owns(cookie) }
        }
        let file = Self.cookiesFile
        guard !cookies.isEmpty else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }

        var lines = ["# Netscape HTTP Cookie File"]
        for cookie in cookies {
            let includeSubdomains = cookie.domain.hasPrefix(".") ? "TRUE" : "FALSE"
            let expiry = cookie.expiresDate.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
            lines.append([
                cookie.domain, includeSubdomains, cookie.path, cookie.isSecure ? "TRUE" : "FALSE",
                expiry, cookie.name, cookie.value,
            ].joined(separator: "\t"))
        }

        do {
            try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path(percentEncoded: false))
            return file
        } catch {
            print("Snag: failed to write cookies: \(error)")
            return nil
        }
    }
}

extension Site {
    var loginURL: URL? {
        switch self {
        case .instagram: URL(string: "https://www.instagram.com/accounts/login/")
        case .tiktok: URL(string: "https://www.tiktok.com/login")
        case .x: URL(string: "https://x.com/i/flow/login")
        case .other: nil
        }
    }

    private var cookieDomains: [String] {
        switch self {
        case .instagram: ["instagram.com"]
        case .tiktok: ["tiktok.com"]
        case .x: ["x.com", "twitter.com"]
        case .other: []
        }
    }

    /// The cookie that's only present while logged in.
    private var sessionCookieName: String {
        self == .x ? "auth_token" : "sessionid"
    }

    func owns(domain: String) -> Bool {
        let domain = domain.lowercased().trimmingPrefix(".")
        return cookieDomains.contains { domain == $0 || domain.hasSuffix("." + $0) }
    }

    func owns(_ cookie: HTTPCookie) -> Bool {
        owns(domain: cookie.domain)
    }

    func isSessionCookie(_ cookie: HTTPCookie) -> Bool {
        owns(cookie) && cookie.name == sessionCookieName && (cookie.expiresDate.map { $0 > .now } ?? true)
    }
}
