#if os(iOS)
import Foundation

/// Runs `snag_bridge.py` in the CPython embedded in the app (iOS can't spawn
/// processes). The "Install Python" build phase puts the standard library in
/// `python/` and yt-dlp, gallery-dl and their dependencies in `app_packages/`.
/// The share extension runs the same copy, out of the app bundle around it.
nonisolated struct EmbeddedPythonExtractor: MediaExtractor {
    func extract(_ url: URL, cookiesFile: URL?) async throws -> ExtractionResult {
        let data = try await EmbeddedPython.shared.extract(url.absoluteString, cookies: cookiesFile?.path(percentEncoded: false))
        return try Extractors.decode(data)
    }
}

/// Owns the interpreter. All calls run one at a time on a single thread.
private nonisolated final class EmbeddedPython: @unchecked Sendable {
    static let shared = EmbeddedPython()

    private let queue = DispatchQueue(label: "com.yigityurtseven.Snag.python", qos: .userInitiated)
    private var startError: String?
    private var isStarted = false

    func extract(_ url: String, cookies: String?) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.startIfNeeded()
                    var failed: Int32 = 0
                    guard let output = snag_python_extract(url, cookies, &failed) else {
                        throw ExtractionError.failed("Python returned nothing")
                    }
                    defer { free(output) }
                    let text = String(cString: output)
                    if failed != 0 { throw ExtractionError.failed("Engine error: \(text)") }
                    continuation.resume(returning: Data(text.utf8))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func startIfNeeded() throws {
        if isStarted { return }
        if let startError { throw ExtractionError.engineMissing(startError) }

        let bundle = Self.appBundle
        let home = bundle.appending(path: "python")
        guard FileManager.default.fileExists(atPath: home.path(percentEncoded: false)) else {
            startError = "Python isn't in the app bundle. Run scripts/fetch-python-ios.sh and rebuild."
            throw ExtractionError.engineMissing(startError!)
        }

        let version = (try? FileManager.default.contentsOfDirectory(atPath: home.appending(path: "lib").path(percentEncoded: false)))?
            .first { $0.hasPrefix("python3.") } ?? "python3.13"
        let stdlib = home.appending(path: "lib/\(version)")
        let paths = [
            stdlib,
            stdlib.appending(path: "lib-dynload"),
            bundle.appending(path: "app_packages"),
            bundle, // snag_bridge.py
        ].map { $0.path(percentEncoded: false) }

        // yt-dlp and gallery-dl keep caches under XDG_CACHE_HOME; the
        // container's home folder itself isn't writable.
        setenv("XDG_CACHE_HOME", URL.cachesDirectory.path(percentEncoded: false), 1)

        var error = [CChar](repeating: 0, count: 512)
        let executable = bundle.appending(path: "Snag").path(percentEncoded: false)
        let status = withCStrings(paths) { pointers in
            snag_python_start(home.path(percentEncoded: false), executable, pointers, Int32(paths.count), &error, error.count)
        }
        guard status == 0 else {
            startError = "Python failed to start: \(String(cString: error))"
            throw ExtractionError.engineMissing(startError!)
        }
        isStarted = true
    }

    /// Snag.app, also from inside Snag.app/PlugIns/ShareExtension.appex.
    private static var appBundle: URL {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "appex" else { return bundle }
        return bundle.deletingLastPathComponent().deletingLastPathComponent()
    }

    private func withCStrings<R>(_ strings: [String], _ body: ([UnsafePointer<CChar>?]) -> R) -> R {
        let copies = strings.map { strdup($0) }
        defer { copies.forEach { free($0) } }
        return body(copies.map { UnsafePointer($0) })
    }
}
#endif
