import AVFoundation
import Foundation
import ImageIO

/// Reads a downloaded file's shape (width over height) without decoding it:
/// image headers via ImageIO, videos from their track and its rotation.
nonisolated enum MediaAspect {
    static func ratio(of url: URL, kind: MediaKind) async -> Double? {
        switch kind {
        case .image: imageRatio(url)
        case .video: await videoRatio(url)
        }
    }

    private static func imageRatio(_ url: URL) -> Double? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0 else { return nil }
        // EXIF orientations 5–8 are rotated a quarter turn.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? height / width : width / height
    }

    private static func videoRatio(_ url: URL) async -> Double? {
        guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return abs(rect.width) / abs(rect.height)
    }
}
