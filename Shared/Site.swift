import Foundation

nonisolated enum Site: String, Codable, CaseIterable, Sendable {
    case instagram, tiktok, x, other

    init(url: URL) {
        let host = url.host()?.lowercased() ?? ""
        func matches(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }

        if matches("instagram.com") { self = .instagram }
        else if matches("tiktok.com") { self = .tiktok }
        else if matches("x.com") || matches("twitter.com") { self = .x }
        else { self = .other }
    }

    var displayName: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .x: "X"
        case .other: "Link"
        }
    }

    var symbol: String {
        switch self {
        case .instagram: "camera"
        case .tiktok: "music.note"
        case .x: "xmark"
        case .other: "link"
        }
    }

    /// Finds the first web link in shared text, e.g. "Check this out https://…".
    static func firstLink(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range)?.url.flatMap {
            ["http", "https"].contains($0.scheme?.lowercased()) ? $0 : nil
        }
    }
}
