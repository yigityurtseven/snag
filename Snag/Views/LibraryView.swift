import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    var body: some View {
        #if os(macOS)
        MacLibraryView()
        #else
        PhoneLibraryView()
        #endif
    }
}

private extension LibraryStore {
    func items(matching filter: LibraryFilter) -> [MediaItem] {
        items.filter(filter.matches)
    }
}

#if os(iOS)
// MARK: iPhone / iPad

private struct PhoneLibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(LinkProcessor.self) private var processor
    @Namespace private var zoom
    @State private var filter = LibraryFilter.all
    @State private var openItem: MediaItem?
    @State private var isAddingLink = false
    @State private var isShowingSettings = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.items.isEmpty {
                    OnboardingView().padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        FilterChips(selection: $filter)
                        let items = store.items(matching: filter)
                        if items.isEmpty {
                            Text(filter.emptyMessage)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                        } else {
                            LibraryGrid(items: items, namespace: zoom) { openItem = $0 }
                                .padding(.horizontal, 12)
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Snag")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    LibraryLayoutMenu()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                }
            }
            .overlay(alignment: .bottomTrailing) { addButton }
            .fullScreenCover(item: $openItem) { item in
                MediaViewer(itemID: item.id)
                    .navigationTransition(.zoom(sourceID: item.id, in: zoom))
            }
            // Tapping a download's Live Activity or notification opens its post.
            .onOpenURL { url in
                guard url.scheme == "snag", url.host() == "item",
                      let id = UUID(uuidString: url.lastPathComponent), let item = store.item(id) else { return }
                openItem = item
            }
            .onChange(of: OpenItemRequest.shared.itemID, initial: true) { _, id in
                guard let id else { return }
                OpenItemRequest.shared.itemID = nil
                // A post the share extension just handed over may not be in the library yet.
                processor.ingestSharedDownloads()
                if let item = store.item(id) { openItem = item }
            }
            .sheet(isPresented: $isAddingLink) {
                AddLinkView()
                    .presentationDetents([.height(300)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
        }
        // First launch: show how easy it is.
        .fullScreenCover(isPresented: Binding(get: { !hasSeenWelcome }, set: { if !$0 { hasSeenWelcome = true } })) {
            WelcomeView { hasSeenWelcome = true }
        }
    }
}

private extension PhoneLibraryView {
    /// Floats over the library in the bottom right corner.
    var addButton: some View {
        Button { isAddingLink = true } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)
        .padding(.trailing, 20)
        .padding(.bottom, 12)
        .accessibilityLabel("Add Link")
    }
}

private struct FilterChips: View {
    @Binding var selection: LibraryFilter

    var body: some View {
        ScrollView(.horizontal) {
            // Liquid Glass chips; the selected one takes the app's tint.
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(LibraryFilter.kinds + LibraryFilter.sites) { filter in
                        let isSelected = filter == selection
                        Button {
                            withAnimation(.snappy) { selection = filter }
                        } label: {
                            Group {
                                if case .site(let site) = filter {
                                    HStack(spacing: 6) {
                                        SiteBadge(site: site, size: 20)
                                        Text(filter.title)
                                    }
                                } else {
                                    Text(filter.title)
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.white : .primary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            isSelected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                            in: .capsule
                        )
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                // Room for the glass's shadow, which the scroll view would clip.
                .padding(.vertical, 6)
            }
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
#endif

#if os(macOS)
// MARK: Mac

private struct MacLibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(LinkProcessor.self) private var processor
    @Namespace private var zoom
    @State private var filter: LibraryFilter? = .all
    @State private var path: [MediaItem.ID] = []
    @State private var linkText = ""
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            List(selection: $filter) {
                Section("Library") {
                    ForEach(LibraryFilter.kinds) { row($0) }
                }
                Section("Sources") {
                    ForEach(LibraryFilter.sites) { row($0) }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) {
                SettingsLink {
                    Label("Accounts & Engine", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(12)
            }
        } detail: {
            NavigationStack(path: $path) {
                library
                    .navigationDestination(for: MediaItem.ID.self) { id in
                        MediaViewer(itemID: id)
                    }
            }
        }
        .onChange(of: filter) { path = [] }
        .toolbar {
            ToolbarItem(placement: .principal) {
                TextField("Paste a link to download", text: $linkText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 340)
                    .onSubmit(submitTypedLink)
            }
            ToolbarItem(placement: .primaryAction) {
                LibraryLayoutMenu()
            }
        }
    }

    private var library: some View {
        let filter = filter ?? .all
        let items = store.items(matching: filter)
        return ScrollView {
            if store.items.isEmpty {
                OnboardingView().padding(.top, 40)
            } else if items.isEmpty {
                Text(filter.emptyMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
            } else {
                LibraryGrid(items: items, namespace: zoom) { path.append($0.id) }
                    .padding(16)
            }
        }
        .safeAreaInset(edge: .top) { EngineBanner() }
        .navigationTitle(filter.title)
        .navigationSubtitle("\(items.count) \(items.count == 1 ? "item" : "items")")
        .onPasteCommand(of: [.url, .plainText]) { providers in
            submit(providers)
        }
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach(processor.submit)
            return !urls.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(.tint.opacity(0.08), in: .rect(cornerRadius: 16))
                    .overlay { Label("Drop to download", systemImage: "arrow.down.circle").font(.title2.bold()) }
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
    }

    private func row(_ filter: LibraryFilter) -> some View {
        let count = store.items(matching: filter).count
        return Group {
            if case .site(let site) = filter {
                Label { Text(filter.title) } icon: { SiteBadge(site: site, size: 18) }
            } else {
                Label(filter.title, systemImage: filter.symbol)
            }
        }
        .badge(count)
        .tag(filter)
    }

    private func submitTypedLink() {
        guard let link = Site.firstLink(in: linkText) else { return }
        processor.submit(link)
        linkText = ""
    }

    private func submit(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadTransferable(type: String.self) { result in
                guard let text = try? result.get(), let link = Site.firstLink(in: text) else { return }
                Task { @MainActor in processor.submit(link) }
            }
        }
    }
}
#endif
