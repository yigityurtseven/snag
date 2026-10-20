import ActivityKit
import SwiftUI
import WidgetKit

/// A post downloading in Snag, on the Lock Screen and in the Dynamic Island.
struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            LockScreenView(site: context.attributes.site, state: context.state)
                .padding(16)
                .activityBackgroundTint(.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(DownloadActivityAttributes.url(for: context.attributes.itemID))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SiteBadge(site: context.attributes.site, size: 36)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StatusGlyph(state: state, size: 36)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(state.headline).font(.headline).lineLimit(1)
                        Text(state.detail(site: context.attributes.site))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if state.phase == .finding || state.phase == .downloading {
                        ProgressBar(state: state).padding(.horizontal, 8).padding(.top, 6)
                    }
                }
            } compactLeading: {
                SiteBadge(site: context.attributes.site, size: 22)
            } compactTrailing: {
                StatusGlyph(state: state, size: 22)
            } minimal: {
                StatusGlyph(state: state, size: 22)
            }
            .widgetURL(DownloadActivityAttributes.url(for: context.attributes.itemID))
            .keylineTint(.accentColor)
        }
    }
}

private struct LockScreenView: View {
    let site: Site
    let state: DownloadActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SiteBadge(site: site, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.headline).font(.headline)
                    Text(state.detail(site: site))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                StatusGlyph(state: state, size: 40)
            }
            if state.phase == .finding || state.phase == .downloading {
                ProgressBar(state: state)
            }
        }
        .foregroundStyle(.white)
    }
}

/// A ring that fills as the files come in, then a checkmark or a warning.
private struct StatusGlyph: View {
    let state: DownloadActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        ZStack {
            switch state.phase {
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .resizable()
                    .foregroundStyle(.orange)
            case .finding:
                Circle().stroke(.white.opacity(0.25), lineWidth: size * 0.12)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: size * 0.42, weight: .bold))
            case .downloading:
                Circle().stroke(.white.opacity(0.25), lineWidth: size * 0.12)
                Circle()
                    .trim(from: 0, to: max(state.progress, 0.03))
                    .stroke(.tint, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "arrow.down")
                    .font(.system(size: size * 0.42, weight: .bold))
            }
        }
        .frame(width: size, height: size)
        .contentTransition(.symbolEffect(.replace))
    }
}

private struct ProgressBar: View {
    let state: DownloadActivityAttributes.ContentState

    var body: some View {
        if state.phase == .finding {
            // Extraction has no measurable progress.
            ProgressView(timerInterval: Date.now...Date.now.addingTimeInterval(20), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .labelsHidden()
                .tint(.white.opacity(0.5))
        } else {
            ProgressView(value: state.progress).tint(.accentColor)
        }
    }
}

private extension DownloadActivityAttributes.ContentState {
    var headline: String {
        switch phase {
        case .finding: "Finding media…"
        case .downloading: fileCount > 1 ? "Downloading \(fileCount) items" : "Downloading"
        case .done: "Downloaded"
        case .failed: "Couldn't download"
        }
    }

    func detail(site: Site) -> String {
        let source = uploader ?? site.displayName
        switch phase {
        case .downloading: return "\(source) · \(Int(progress * 100))%"
        case .done: return fileCount > 1 ? "\(fileCount) items from \(source)" : "From \(source)"
        case .failed: return "Open Snag to try again"
        case .finding: return source
        }
    }
}
