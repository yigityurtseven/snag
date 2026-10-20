import Foundation

nonisolated enum MediaKind: String, Codable, Sendable {
    case image, video
}

/// One file inside a post (a carousel has several).
nonisolated struct MediaFile: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var kind: MediaKind
    var remoteURL: URL
    var headers: [String: String] = [:]
    var fileExtension: String
    /// File name inside `AppGroup.mediaDirectory`, set once downloaded.
    var localFilename: String?
    /// Width over height, measured once downloaded. The masonry layout uses it.
    var aspectRatio: Double?

    var localURL: URL? {
        localFilename.map { AppGroup.mediaDirectory.appending(path: $0) }
    }
}

nonisolated enum ItemStatus: Codable, Hashable, Sendable {
    case extracting
    case downloading
    case done
    case failed(String)
}

/// A shared post and everything downloaded from it.
nonisolated struct MediaItem: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var sourceURL: URL
    var site: Site
    var title: String?
    var uploader: String?
    var createdAt = Date.now
    var status: ItemStatus = .extracting
    var files: [MediaFile] = []
    /// Set when the share extension started the downloads, in a background
    /// session of its own that the app reconnects to.
    var downloadSession: String?

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        self.site = Site(url: sourceURL)
    }

    var downloadedFiles: [MediaFile] { files.filter { $0.localFilename != nil } }

    /// The shape of the post's first file, kept between 9:16 and 16:10 so one
    /// panorama or very tall photo doesn't take over the masonry. 3:4 until known.
    var displayAspectRatio: Double {
        let ratio = files.lazy.compactMap(\.aspectRatio).first ?? 3.0 / 4.0
        return min(max(ratio, 9.0 / 16.0), 1.6)
    }
}
