import AVKit
import SwiftUI

/// Full-screen, dark viewer for one post: swipe through carousel items,
/// pinch or double-tap photos to zoom, videos loop. Who posted it and the
/// actions float at the bottom as glass controls, nothing to drag, so swiping
/// down on the media always closes the viewer.
struct MediaViewer: View {
    let itemID: MediaItem.ID

    @Environment(LibraryStore.self) private var store
    @Environment(LinkProcessor.self) private var processor
    @Environment(Accounts.self) private var accounts
    @Environment(\.itemActions) private var actions
    @Environment(\.dismiss) private var dismiss
    @State private var page: MediaFile.ID?
    @State private var loginSite: Site?
    @State private var showsCaption = false
    @State private var showsChrome = true
    @State private var isZoomed = false
    @State private var panelHeight: CGFloat = 0
    @State private var safeArea = EdgeInsets()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let item = store.item(itemID) {
                content(for: item)
                    // An overlay rather than a sheet: a sheet on top would stop
                    // the viewer from being swiped away.
                    .overlay(alignment: .bottom) {
                        if showsChrome, Self.hasMedia(item) {
                            bottomBar(for: item)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .top) {
                        if showsChrome { topBar(for: item).transition(.opacity) }
                    }
            }
        }
        .sheet(item: $loginSite) { site in
            LoginSheet(site: site) { processor.retry(itemID) }
        }
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeArea = $0 }
        // Saving can remove the post from Snag; nothing's left to show.
        .onChange(of: store.item(itemID) == nil) { _, isGone in
            if isGone { dismiss() }
        }
        // Panning a zoomed photo downward shouldn't close the viewer.
        .interactiveDismissDisabled(isZoomed)
        .environment(\.colorScheme, .dark)
        #if os(iOS)
        // The library's toasts sit under this cover; show them here, above the panel.
        .toastOverlay(bottomPadding: showsChrome ? panelHeight + 16 : 24)
        #endif
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    // MARK: Media

    @ViewBuilder private func content(for item: MediaItem) -> some View {
        switch item.status {
        case .extracting:
            ProgressView("Finding media…").tint(.white).foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .onTapGesture(perform: toggleChrome)
        case .failed(let message):
            failure(item: item, message: message)
        case .downloading, .done:
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(item.files) { file in
                        MediaPage(file: file, videoInsets: videoInsets, onTap: toggleChrome) { zoomed in
                            isZoomed = zoomed
                            // Zooming in is for looking; get the controls out of the way, like Photos.
                            if zoomed, showsChrome { toggleChrome() }
                        }
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(file.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .scrollIndicators(.hidden)
            // A zoomed photo pans instead of flipping to the next one.
            .scrollDisabled(isZoomed)
            .ignoresSafeArea()
        }
    }

    /// Tap the media to hide the controls, like Photos.
    private func toggleChrome() {
        withAnimation(.smooth(duration: 0.25)) { showsChrome.toggle() }
    }

    /// Keeps a video's own controls clear of the top bar and the panel. Photos
    /// stay full-bleed, since they can be zoomed and panned out from under them.
    private var videoInsets: EdgeInsets {
        guard showsChrome else { return EdgeInsets(top: safeArea.top, leading: 0, bottom: safeArea.bottom, trailing: 0) }
        return EdgeInsets(top: safeArea.top + 52, leading: 0, bottom: safeArea.bottom + panelHeight + 8, trailing: 0)
    }

    private func currentFile(in item: MediaItem) -> MediaFile? {
        item.files.first { $0.id == page } ?? item.files.first
    }

    private func failure(item: MediaItem, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Couldn't download this post").font(.title3.bold())
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(6)
            VStack(spacing: 10) {
                if Self.needsLogin(message), Accounts.supported.contains(item.site), !accounts.loggedIn.contains(item.site) {
                    Button { loginSite = item.site } label: {
                        Label("Log in to \(item.site.displayName)", systemImage: "person.crop.circle")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(.glassProminent)
                }
                Button { processor.retry(item.id) } label: {
                    Label("Try Again", systemImage: "arrow.clockwise").frame(maxWidth: 260)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(32)
    }

    // MARK: Chrome

    private func topBar(for item: MediaItem) -> some View {
        HStack {
            #if os(iOS)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 36, height: 36)
            }
            .accessibilityLabel("Close")
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            #endif
            Spacer()
            if item.files.count > 1 {
                let index = (item.files.firstIndex { $0.id == page } ?? 0) + 1
                Text("\(index) / \(item.files.count)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: index)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Panel

    private static func hasMedia(_ item: MediaItem) -> Bool {
        item.status == .done || item.status == .downloading
    }

    /// Like the design: a pill with who posted it on the left, more actions
    /// and save on the right. Tapping the pill shows the caption above it.
    private func bottomBar(for item: MediaItem) -> some View {
        let caption = item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCaption = !(caption ?? "").isEmpty
        return GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                if showsCaption, let caption, hasCaption {
                    ScrollView {
                        Text(caption)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: 180)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    .onTapGesture { toggleCaption() }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                HStack(spacing: 12) {
                    authorPill(for: item, hasCaption: hasCaption)
                    Spacer(minLength: 0)
                    Menu {
                        ItemMenu(item: item)
                    } label: {
                        circleIcon("ellipsis")
                    }
                    .menuIndicator(.hidden)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("More")

                    saveButton(for: item)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
            }
        }
        .tint(.primary)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: 600)
    }

    private func authorPill(for item: MediaItem, hasCaption: Bool) -> some View {
        HStack(spacing: 10) {
            SiteBadge(site: item.site, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.uploader ?? item.site.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.createdAt, format: .relative(presentation: .named))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 20)
        .frame(height: 56)
        .contentShape(.capsule)
        .glassEffect(hasCaption ? .regular.interactive() : .regular, in: .capsule)
        .onTapGesture { if hasCaption { toggleCaption() } }
        .accessibilityElement(children: .combine)
        .accessibilityHint(hasCaption ? (showsCaption ? "Hides the caption" : "Shows the caption") : "")
        .accessibilityAddTraits(hasCaption ? .isButton : [])
    }

    private func circleIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 56, height: 56)
            .contentShape(.circle)
    }

    private func toggleCaption() {
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) { showsCaption.toggle() }
    }

    /// Saves straight away; for a carousel, asks whether it's the page on
    /// screen or all of them.
    @ViewBuilder private func saveButton(for item: MediaItem) -> some View {
        let current = currentFile(in: item)
        if item.files.count > 1, let current {
            let noun = current.kind == .video ? "Video" : "Photo"
            Menu {
                Button("Save This \(noun)", systemImage: current.kind == .video ? "video" : "photo") {
                    Task { await actions?.saveToPhotos([current]) }
                }
                .disabled(current.localFilename == nil)
                Button("Save All \(item.files.count)", systemImage: "square.stack") {
                    Task { await actions?.saveToPhotos(item) }
                }
                .disabled(item.status != .done)
            } label: {
                circleIcon("square.and.arrow.down")
            }
            .menuIndicator(.hidden)
            .disabled(current.localFilename == nil && item.status != .done)
            .accessibilityLabel("Save to Photos")
        } else {
            Button {
                Task { await actions?.saveToPhotos(item) }
            } label: {
                circleIcon("square.and.arrow.down")
            }
            .buttonStyle(.plain)
            .disabled(item.status != .done)
            .accessibilityLabel("Save to Photos")
        }
    }

    static func needsLogin(_ message: String) -> Bool {
        let message = message.lowercased()
        return ["login", "log in", "logged in", "cookies", "authenticat", "private"].contains { message.contains($0) }
    }
}

// MARK: Pages

private struct MediaPage: View {
    let file: MediaFile
    let videoInsets: EdgeInsets
    let onTap: () -> Void
    let onZoomChange: (Bool) -> Void

    var body: some View {
        if let url = file.localURL {
            switch file.kind {
            case .video:
                LoopingVideo(url: url)
                    .padding(videoInsets)
                    .animation(.smooth(duration: 0.25), value: videoInsets)
                    .contentShape(.rect)
                    .onTapGesture(perform: onTap)
            case .image:
                ZoomableImage(url: url, onTap: onTap, onZoomChange: onZoomChange)
            }
        } else {
            ProgressView().tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .onTapGesture(perform: onTap)
        }
    }
}

/// Plays while at least half visible, loops, and pauses when swiped away.
private struct LoopingVideo: View {
    let url: URL
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                if looper == nil {
                    looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
                }
            }
            .onScrollVisibilityChange(threshold: 0.5) { visible in
                visible ? player.play() : player.pause()
            }
            .onDisappear { player.pause() }
    }
}
