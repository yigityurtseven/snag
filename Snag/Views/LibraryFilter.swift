import Foundation

enum LibraryFilter: Hashable, Identifiable {
    case all, videos, photos
    case site(Site)

    static let kinds: [LibraryFilter] = [.all, .videos, .photos]
    static let sites: [LibraryFilter] = Accounts.supported.map { .site($0) }

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .videos: "Videos"
        case .photos: "Photos"
        case .site(let site): site.displayName
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .videos: "play.rectangle"
        case .photos: "photo"
        case .site(let site): site.symbol
        }
    }

    func matches(_ item: MediaItem) -> Bool {
        switch self {
        case .all: true
        case .videos: item.files.contains { $0.kind == .video }
        case .photos: item.files.contains { $0.kind == .image }
        case .site(let site): item.site == site
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: "Nothing here yet."
        case .videos: "No videos yet."
        case .photos: "No photos yet."
        case .site(let site): "Nothing from \(site.displayName) yet."
        }
    }
}
