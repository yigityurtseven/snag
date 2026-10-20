#if os(macOS)
import Foundation

/// Runs `snag_bridge.py` with the Python that `EngineInstaller` sets up.
/// Set `SNAG_PYTHON` in the scheme to use a different interpreter.
nonisolated struct ProcessExtractor: MediaExtractor {
    static var pythonURL: URL {
        if let custom = ProcessInfo.processInfo.environment["SNAG_PYTHON"] {
            return URL(filePath: custom)
        }
        return EngineInstaller.pythonURL
    }

    func extract(_ url: URL, cookiesFile: URL?) async throws -> ExtractionResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.run(url, cookiesFile: cookiesFile)
        }.value
    }

    private static func run(_ url: URL, cookiesFile: URL?) throws -> ExtractionResult {
        let python = pythonURL
        guard FileManager.default.isExecutableFile(atPath: python.path(percentEncoded: false)) else {
            throw ExtractionError.engineMissing("Install it from the banner in your library.")
        }
        guard let script = Bundle.main.url(forResource: "snag_bridge", withExtension: "py") else {
            throw ExtractionError.engineMissing("snag_bridge.py is missing from the app bundle.")
        }

        var arguments = [script.path(percentEncoded: false), url.absoluteString]
        if let cookiesFile { arguments += ["--cookies", cookiesFile.path(percentEncoded: false)] }

        let process = Process()
        let stdout = Pipe()
        process.executableURL = python
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        try process.run()
        // Read before waiting so a large JSON payload can't fill the pipe and stall.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return try Extractors.decode(data)
    }
}
#endif
