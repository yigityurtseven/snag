import Foundation
import Observation

/// The list of downloaded posts, persisted as JSON in the app group container.
@Observable
final class LibraryStore {
    private(set) var items: [MediaItem] = []

    init() {
        load()
        // Posts saved before shapes were recorded get them once.
        Task { await measureMissingAspectRatios() }
    }

    func item(_ id: MediaItem.ID) -> MediaItem? {
        items.first { $0.id == id }
    }

    func insert(_ item: MediaItem) {
        items.insert(item, at: 0)
        save()
    }

    func update(_ id: MediaItem.ID, _ change: (inout MediaItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        save()
    }

    func delete(_ id: MediaItem.ID) {
        guard let item = item(id) else { return }
        for url in item.files.compactMap(\.localURL) {
            try? FileManager.default.removeItem(at: url)
        }
        items.removeAll { $0.id == id }
        save()
    }

    /// Measures every downloaded file that doesn't know its shape yet.
    func measureMissingAspectRatios() async {
        let missing = items.flatMap { item in
            item.files.filter { $0.aspectRatio == nil && $0.localURL != nil }.map { (item.id, $0) }
        }
        guard !missing.isEmpty else { return }
        var ratios: [MediaFile.ID: Double] = [:]
        for (_, file) in missing {
            if let url = file.localURL { ratios[file.id] = await MediaAspect.ratio(of: url, kind: file.kind) }
        }
        // One save for the lot.
        for itemIndex in items.indices {
            for fileIndex in items[itemIndex].files.indices {
                if let ratio = ratios[items[itemIndex].files[fileIndex].id] {
                    items[itemIndex].files[fileIndex].aspectRatio = ratio
                }
            }
        }
        save()
    }

    private func measure(_ file: MediaFile, in itemID: MediaItem.ID) async {
        guard let url = file.localURL, let ratio = await MediaAspect.ratio(of: url, kind: file.kind) else { return }
        update(itemID) { item in
            if let index = item.files.firstIndex(where: { $0.id == file.id }) {
                item.files[index].aspectRatio = ratio
            }
        }
    }

    /// Records a finished (or failed) file and settles the item's status.
    func finishFile(item id: MediaItem.ID, file fileID: MediaFile.ID, filename: String?, error: String?) {
        defer {
            if filename != nil, let file = item(id)?.files.first(where: { $0.id == fileID }) {
                Task { await measure(file, in: id) }
            }
        }
        update(id) { item in
            guard let index = item.files.firstIndex(where: { $0.id == fileID }) else { return }
            if let filename {
                item.files[index].localFilename = filename
            }
            if let error {
                item.status = .failed(error)
            } else if item.files.allSatisfy({ $0.localFilename != nil }) {
                item.status = .done
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: AppGroup.libraryFile) else { return }
        items = (try? JSONDecoder().decode([MediaItem].self, from: data)) ?? []
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: AppGroup.libraryFile, options: .atomic)
        } catch {
            print("Snag: failed to save library: \(error)")
        }
    }
}
