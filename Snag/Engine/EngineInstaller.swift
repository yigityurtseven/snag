#if os(macOS)
import Foundation
import Observation

/// Installs and updates the macOS download engine: a self-contained Python
/// (python-build-standalone) with yt-dlp and gallery-dl, kept in
/// Application Support so users don't need Python or a terminal.
@Observable
final class EngineInstaller {
    enum State: Equatable {
        case checking
        case notInstalled
        case working(String)
        case ready(versions: String)
        case failed(String)
    }

    private(set) var state = State.checking

    nonisolated static var engineDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Snag/engine", directoryHint: .isDirectory)
    }
    nonisolated static var pythonDirectory: URL {
        engineDirectory.appending(path: "python", directoryHint: .isDirectory)
    }
    nonisolated static var pythonURL: URL {
        pythonDirectory.appending(path: "bin/python3")
    }

    var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: Self.pythonURL.path(percentEncoded: false)) }
    var isWorking: Bool {
        if case .working = state { true } else { false }
    }

    private static let lastUpdateKey = "engineLastUpdate"
    private static let updateInterval: TimeInterval = 24 * 60 * 60

    /// Checks the install, and updates yt-dlp and gallery-dl at most once a day
    /// since the sites they support change often.
    func refresh() async {
        guard isInstalled else {
            state = .notInstalled
            return
        }
        let lastUpdate = UserDefaults.standard.object(forKey: Self.lastUpdateKey) as? Date ?? .distantPast
        if Date.now.timeIntervalSince(lastUpdate) > Self.updateInterval {
            await update()
        } else {
            await readVersions()
        }
    }

    func install() async {
        guard !isWorking else { return }
        do {
            state = .working("Downloading Python…")
            try await Self.installPython()
            state = .working("Installing yt-dlp and gallery-dl…")
            try await Self.installPackages()
            UserDefaults.standard.set(Date.now, forKey: Self.lastUpdateKey)
            await readVersions()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func update() async {
        guard isInstalled else { return await install() }
        guard !isWorking else { return }
        state = .working("Updating yt-dlp and gallery-dl…")
        do {
            try await Self.installPackages()
            UserDefaults.standard.set(Date.now, forKey: Self.lastUpdateKey)
        } catch {
            // Offline or PyPI hiccup: keep using the installed versions.
            print("Snag: engine update failed: \(error.localizedDescription)")
        }
        await readVersions()
    }

    private func readVersions() async {
        let script = "import yt_dlp, gallery_dl; print(f'yt-dlp {yt_dlp.version.__version__} · gallery-dl {gallery_dl.version.__version__}')"
        do {
            let output = try await Self.run(Self.pythonURL, ["-c", script])
            state = .ready(versions: output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            state = .failed("The engine looks damaged. Reinstall it to fix this.")
        }
    }

    // MARK: Steps

    private nonisolated struct Release: Decodable {
        struct Asset: Decodable {
            var name: String
            var browser_download_url: URL
        }
        var assets: [Asset]
    }

    private nonisolated static func installPython() async throws {
        #if arch(arm64)
        let arch = "aarch64"
        #else
        let arch = "x86_64"
        #endif
        let releaseURL = URL(string: "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest")!
        let (data, _) = try await URLSession.shared.data(from: releaseURL)
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard let asset = release.assets.first(where: {
            $0.name.hasPrefix("cpython-3.13.") && $0.name.hasSuffix("-\(arch)-apple-darwin-install_only_stripped.tar.gz")
        }) else {
            throw InstallError("Couldn't find a Python build for this Mac.")
        }

        let (archive, _) = try await URLSession.shared.download(from: asset.browser_download_url)
        defer { try? FileManager.default.removeItem(at: archive) }

        // The archive holds a single top-level "python" folder.
        let fileManager = FileManager.default
        let staging = engineDirectory.appending(path: "staging", directoryHint: .isDirectory)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try await run(URL(filePath: "/usr/bin/tar"), ["-xzf", archive.path(percentEncoded: false), "-C", staging.path(percentEncoded: false)])
        try? fileManager.removeItem(at: pythonDirectory)
        try fileManager.moveItem(at: staging.appending(path: "python"), to: pythonDirectory)
    }

    private nonisolated static func installPackages() async throws {
        if (try? await run(pythonURL, ["-m", "pip", "--version"])) == nil {
            try await run(pythonURL, ["-m", "ensurepip", "--upgrade"])
        }
        try await run(pythonURL, [
            "-m", "pip", "install", "--upgrade", "--disable-pip-version-check", "--no-input",
            "yt-dlp", "gallery-dl",
        ])
    }

    // MARK: Helpers

    private nonisolated struct InstallError: LocalizedError {
        var errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Runs a command and returns its output, throwing with the tail of the
    /// output if it fails.
    @discardableResult
    private nonisolated static func run(_ executable: URL, _ arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "PYTHONNOUSERSITE": "1"]

            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let text = String(decoding: data, as: UTF8.self)
            guard process.terminationStatus == 0 else {
                let tail = text.split(separator: "\n").suffix(3).joined(separator: "\n")
                throw InstallError("\(executable.lastPathComponent) failed: \(tail)")
            }
            return text
        }.value
    }
}
#endif
