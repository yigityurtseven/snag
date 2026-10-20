import AVFoundation
import SwiftUI

/// The saved posts, as even tiles or masonry columns (see `LibraryLayout`).
/// Doesn't scroll itself so callers can put headers above it.
struct LibraryGrid: View {
    let items: [MediaItem]
    var namespace: Namespace.ID
    var onOpen: (MediaItem) -> Void

    @AppStorage(LibraryLayout.key) private var layout = LibraryLayout.masonry
    @AppStorage(LibraryDensity.key) private var density = LibraryDensity.regular
    @AppStorage(LibraryLayoutKey.showsInfo) private var showsInfo = true
    @State private var width: CGFloat = 0

    var body: some View {
        Group {
            switch layout {
            case .grid: grid
            case .masonry: masonry
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .animation(.snappy, value: items.map(\.id))
    }

    /// Both layouts use the same count, so switching keeps tiles roughly in place.
    private var columnCount: Int {
        guard width > 0 else { return 3 }
        return max(2, Int((width + density.spacing) / (density.minimumWidth + density.spacing)))
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: density.spacing), count: columnCount)
        return LazyVGrid(columns: columns, spacing: density.spacing) {
            ForEach(items) { item in
                tile(item, aspectRatio: 3 / 4)
            }
        }
    }

    private var masonry: some View {
        let columns = MasonryColumns.fromEnd(items.map(\.displayAspectRatio), count: columnCount)
        return HStack(alignment: .top, spacing: density.spacing) {
            ForEach(columns.indices, id: \.self) { column in
                LazyVStack(spacing: density.spacing) {
                    ForEach(columns[column].map { items[$0] }) { item in
                        tile(item, aspectRatio: item.displayAspectRatio)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func tile(_ item: MediaItem, aspectRatio: Double) -> some View {
        Button { onOpen(item) } label: {
            LibraryCard(item: item, aspectRatio: aspectRatio, cornerRadius: density.cornerRadius,
                        showsInfo: showsInfo, isCompact: density == .compact)
        }
        .buttonStyle(CardButtonStyle())
        .contextMenu { ItemMenu(item: item) }
        #if os(iOS)
        .matchedTransitionSource(id: item.id, in: namespace) { source in
            source.clipShape(.rect(cornerRadius: density.cornerRadius))
        }
        #endif
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

/// Puts each post in the shortest column, so the columns end even.
enum MasonryColumns {
    /// Indices into `ratios` (width over height) per column, in order.
    static func shortestFirst(_ ratios: [Double], count: Int) -> [[Int]] {
        var columns = Array(repeating: [Int](), count: max(count, 1))
        var heights = Array(repeating: 0.0, count: columns.count)
        for (index, ratio) in ratios.enumerated() {
            let shortest = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[shortest].append(index)
            heights[shortest] += 1 / max(ratio, 0.01)
        }
        return columns
    }

    /// Filled from the oldest post, each column still newest first. A new
    /// download then lands at the top of one column and nothing else moves.
    static func fromEnd(_ ratios: [Double], count: Int) -> [[Int]] {
        let last = ratios.count - 1
        return shortestFirst(ratios.reversed(), count: count).map { $0.reversed().map { last - $0 } }
    }
}

private struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

struct LibraryCard: View {
    let item: MediaItem
    var aspectRatio: Double = 3 / 4
    var cornerRadius: CGFloat = 14
    /// Who posted it and the video's length, along the bottom, and the site's logo.
    var showsInfo = true
    /// Small tiles get smaller badges.
    var isCompact = false

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .background { background }
            .overlay(alignment: .bottom) { if showsInfo && !isCompact { footer } }
            .overlay(alignment: .topLeading) {
                if showsInfo { SiteBadge(site: item.site, size: isCompact ? 16 : 20).padding(isCompact ? 5 : 7) }
            }
            .overlay(alignment: .topTrailing) { kindBadge.padding(isCompact ? 5 : 7) }
            .overlay { status }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .contentShape(.rect(cornerRadius: cornerRadius))
    }

    @ViewBuilder private var background: some View {
        if let url = item.downloadedFiles.first?.localURL {
            MediaThumbnail(url: url)
        } else {
            Rectangle().fill(item.site.gradient.opacity(0.35))
        }
    }

    @ViewBuilder private var footer: some View {
        if item.status == .done {
            HStack(spacing: 4) {
                Text(item.uploader ?? item.site.displayName)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let video = item.files.first(where: { $0.kind == .video })?.localURL, item.files.count == 1 {
                    VideoDuration(url: video)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 2)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
        }
    }

    @ViewBuilder private var kindBadge: some View {
        let symbol: String? = item.files.count > 1 ? "square.fill.on.square.fill"
            : item.files.first?.kind == .video ? "play.fill" : nil
        if let symbol, item.status == .done {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
    }

    @ViewBuilder private var status: some View {
        switch item.status {
        case .extracting:
            StatusOverlay(title: "Finding media…") { ProgressView().controlSize(.small) }
        case .downloading:
            let done = item.downloadedFiles.count
            StatusOverlay(title: item.files.count > 1 ? "\(done) of \(item.files.count)" : "Downloading…") {
                ProgressView(value: Double(done), total: Double(max(item.files.count, 1)))
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }
        case .failed:
            StatusOverlay(title: "Failed") {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }
        case .done:
            EmptyView()
        }
    }
}

private struct StatusOverlay<Icon: View>: View {
    let title: String
    @ViewBuilder var icon: Icon

    var body: some View {
        VStack(spacing: 6) {
            icon
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

private struct VideoDuration: View {
    let url: URL
    @State private var text: String?

    var body: some View {
        Text(text ?? "")
            .monospacedDigit()
            .task(id: url) {
                guard let duration = try? await AVURLAsset(url: url).load(.duration) else { return }
                let seconds = Int(duration.seconds.rounded())
                text = String(format: "%d:%02d", seconds / 60, seconds % 60)
            }
    }
}

/// Shown when the whole library is empty.
struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle().fill(Site.instagram.gradient).frame(width: 96, height: 96)
                Image(systemName: "arrow.down")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .pink.opacity(0.3), radius: 20, y: 10)

            VStack(spacing: 8) {
                Text("Save what you love").font(.title2.bold())
                Text("Photos and videos from Instagram, TikTok and X, kept on your device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                #if os(iOS)
                step(1, "Open a post in Instagram, TikTok or X")
                step(2, "Tap Share, then Snag. The first time, it may be under More.")
                step(3, "It appears here. Save it to Photos with one tap.")
                #else
                step(1, "Copy a link to a post on Instagram, TikTok or X")
                step(2, "Press ⌘V, paste it in the toolbar, or drag it here")
                step(3, "It appears here, ready for Photos or Finder")
                #endif
            }
            .padding(20)
            .frame(maxWidth: 380, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 20))

            #if os(iOS)
            Text("Or tap \(Image(systemName: "plus")) to paste a link.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            #endif
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.tint, in: .circle)
            Text(text).font(.callout)
        }
    }
}
