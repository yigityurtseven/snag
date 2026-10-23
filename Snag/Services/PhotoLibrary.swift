import Foundation
import Photos

enum PhotoLibrary {
    enum SaveError: LocalizedError {
        case notAuthorized

        var errorDescription: String? {
            "Snag doesn't have permission to add to your photo library. You can allow it in Settings."
        }
    }

    /// Settings keys. Both are off until the user turns them on.
    static let autoSaveKey = "autoSaveToPhotos"
    static let removeAfterSavingKey = "removeAfterSaving"

    static var savesAutomatically: Bool { UserDefaults.standard.bool(forKey: autoSaveKey) }
    static var removesAfterSaving: Bool { UserDefaults.standard.bool(forKey: removeAfterSavingKey) }

    /// Only asks for add-only access, never reads the library.
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    /// Adds files to Photos.
    static func save(_ files: [MediaFile]) async throws {
        guard await requestAccess() else { throw SaveError.notAuthorized }

        try await PHPhotoLibrary.shared().performChanges {
            for file in files {
                guard let url = file.localURL else { continue }
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: file.kind == .video ? .video : .photo, fileURL: url, options: nil)
            }
        }
    }
}
