import Foundation

/// Storage shared between the app and the share extension.
nonisolated enum AppGroup {
    static let identifier = "group.com.yigityurtseven.Snag"

    static var containerURL: URL {
        #if os(iOS)
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        #endif
        return directory(URL.applicationSupportDirectory.appending(path: "Snag", directoryHint: .isDirectory))
    }

    static var mediaDirectory: URL { subdirectory("Media") }
    static var pendingDirectory: URL { subdirectory("Pending") }
    static var sharedItemsDirectory: URL { subdirectory("SharedItems") }
    static var finishedFilesDirectory: URL { subdirectory("FinishedFiles") }
    static var libraryFile: URL { containerURL.appending(path: "library.json") }
    /// Logins exported by the app, for the share extension's downloads too.
    static var cookiesFile: URL { containerURL.appending(path: "cookies.txt") }

    private static func subdirectory(_ name: String) -> URL {
        directory(containerURL.appending(path: name, directoryHint: .isDirectory))
    }

    private static func directory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
