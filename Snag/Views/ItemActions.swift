import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Actions shared by the library's context menu and the viewer.
struct ItemActions {
    let store: LibraryStore
    let processor: LinkProcessor
    let toasts: Toasts

    func saveToPhotos(_ item: MediaItem) async {
        await saveToPhotos(item.downloadedFiles)
    }

    /// Saves some of a post's files, e.g. just the carousel page on screen.
    func saveToPhotos(_ files: [MediaFile]) async {
        do {
            try await PhotoLibrary.save(files)
            toasts.show(files.count > 1 ? "Saved \(files.count) items to Photos" : "Saved to Photos")
        } catch {
            toasts.show(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
        }
    }

    func copyLink(_ item: MediaItem) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.sourceURL.absoluteString, forType: .string)
        #else
        UIPasteboard.general.url = item.sourceURL
        #endif
        toasts.show("Link copied", systemImage: "link")
    }

    #if os(macOS)
    func showInFinder(_ item: MediaItem) {
        NSWorkspace.shared.activateFileViewerSelecting(item.downloadedFiles.compactMap(\.localURL))
    }
    #endif

    func delete(_ item: MediaItem) {
        withAnimation(.snappy) { store.delete(item.id) }
    }
}

extension EnvironmentValues {
    @Entry var itemActions: ItemActions?
}

/// Menu items for one library item.
struct ItemMenu: View {
    let item: MediaItem
    @Environment(\.itemActions) private var actions
    @Environment(LinkProcessor.self) private var processor

    var body: some View {
        if let actions {
            if item.status == .done {
                Button(item.files.count > 1 ? "Save All to Photos" : "Save to Photos", systemImage: "square.and.arrow.down") {
                    Task { await actions.saveToPhotos(item) }
                }
                ShareLink(items: item.downloadedFiles.compactMap(\.localURL)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                #if os(macOS)
                Button("Show in Finder", systemImage: "folder") { actions.showInFinder(item) }
                #endif
            }
            if case .failed = item.status {
                Button("Try Again", systemImage: "arrow.clockwise") { processor.retry(item.id) }
            }
            Button("Copy Link", systemImage: "link") { actions.copyLink(item) }
            Link(destination: item.sourceURL) {
                Label("Open in \(item.site.displayName)", systemImage: "arrow.up.forward.app")
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { actions.delete(item) }
        }
    }
}
