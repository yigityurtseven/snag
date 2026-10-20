import Foundation
import Photos

enum PhotoLibrary {
    enum SaveError: LocalizedError {
        case notAuthorized

        var errorDescription: String? {
            "Snag doesn't have permission to add to your photo library. You can allow it in Settings."
        }
    }

    /// Adds files to Photos. Only asks for add-only access, never reads the library.
    static func save(_ files: [MediaFile]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.notAuthorized }

        try await PHPhotoLibrary.shared().performChanges {
            for file in files {
                guard let url = file.localURL else { continue }
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: file.kind == .video ? .video : .photo, fileURL: url, options: nil)
            }
        }
    }
}
