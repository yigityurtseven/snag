import Foundation

/// Resolves a post URL into direct media URLs. Implementations wrap
/// `snag_bridge.py`, so every platform gets the same JSON back.
nonisolated protocol MediaExtractor: Sendable {
    func extract(_ url: URL, cookiesFile: URL?) async throws -> ExtractionResult
}

nonisolated struct ExtractionResult: Decodable, Sendable {
    struct Media: Decodable, Sendable {
        var url: URL
        var kind: MediaKind
        var ext: String
        var headers: [String: String]
    }

    var ok: Bool
    var error: String?
    var site: String?
    var extractor: String?
    var title: String?
    var uploader: String?
    var media: [Media]?
}

nonisolated enum ExtractionError: LocalizedError {
    case engineMissing(String)
    case badOutput(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .engineMissing(let detail): "Download engine not installed. \(detail)"
        case .badOutput(let detail): "Unexpected engine output: \(detail)"
        case .failed(let message): message
        }
    }
}

nonisolated enum Extractors {
    static func platformDefault() -> any MediaExtractor {
        #if os(macOS)
        ProcessExtractor()
        #else
        EmbeddedPythonExtractor()
        #endif
    }

    /// Shared by every extractor: decode the bridge's JSON and surface its error.
    static func decode(_ data: Data) throws -> ExtractionResult {
        let result: ExtractionResult
        do {
            result = try JSONDecoder().decode(ExtractionResult.self, from: data)
        } catch {
            throw ExtractionError.badOutput(String(decoding: data.prefix(500), as: UTF8.self))
        }
        guard result.ok else { throw ExtractionError.failed(result.error ?? "Unknown error") }
        return result
    }
}
