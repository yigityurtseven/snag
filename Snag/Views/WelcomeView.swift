#if os(iOS)
import SwiftUI

/// Shown on first launch (and from Settings): saving is just sharing a post
/// to Snag, here's how to keep Snag handy in the share sheet, and turning on
/// the notification that says it's saved.
struct WelcomeView: View {
    let onFinish: () -> Void

    @State private var page = 0
    private let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                sharePage.tag(0)
                favoritesPage.tag(1)
                notificationsPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: page)

            footer
        }
        .background(Color(.systemBackground))
    }

    // MARK: Pages

    private var sharePage: some View {
        page(title: "Share it to Snag",
             message: "See a post you love on Instagram, TikTok or X? Tap Share, then Snag. That's it: it downloads in the background and lands in your library.") {
            ShareDemo()
        }
    }

    private var favoritesPage: some View {
        page(title: "Keep Snag one tap away",
             message: "The first time, Snag may be hiding at the end of the share sheet. Pin it to the front:") {
            VStack(alignment: .leading, spacing: 18) {
                step(1, "In any app, tap \(Image(systemName: "square.and.arrow.up")) Share.")
                step(2, "Scroll the row of apps to the end and tap More.")
                step(3, "Tap Edit, then \(Image(systemName: "plus.circle.fill")) next to Snag to add it to Favorites.")
            }
            .padding(24)
            .frame(maxWidth: 380, alignment: .leading)
            .background(.fill.quaternary, in: .rect(cornerRadius: 24))
            .overlay(alignment: .top) {
                SnagMark(size: 64)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                    .offset(y: -40)
            }
            .padding(.top, 40)
        }
    }

    private var notificationsPage: some View {
        page(title: "Know when it's saved",
             message: "Snag can tell you when a post you shared has finished downloading, so you never have to open the app to check.") {
            NotificationPreview()
        }
    }

    private func page<Art: View>(title: String, message: String, @ViewBuilder art: () -> Art) -> some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)
            art()
                .frame(maxHeight: 380)
            VStack(spacing: 10) {
                Text(title)
                    .font(.title.bold())
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            Spacer(minLength: 0)
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.tint, in: .circle)
            Text(text).font(.callout)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: index == page ? 22 : 8, height: 8)
                }
            }
            .animation(.snappy, value: page)
            .accessibilityHidden(true)

            Button(action: primaryAction) {
                Text(page == pageCount - 1 ? "Turn On Notifications" : "Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            Button(page == pageCount - 1 ? "Not Now" : "Skip", action: onFinish)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func primaryAction() {
        guard page == pageCount - 1 else {
            withAnimation(.snappy) { page += 1 }
            return
        }
        // Asked here, so the app doesn't ask again after the first post.
        UserDefaults.standard.set(true, forKey: "askedForNotifications")
        Task {
            await DownloadNotifications.requestAuthorization()
            onFinish()
        }
    }
}

// MARK: - Share demo

/// A post, the share sheet sliding up, a tap on Snag, and the post landing in
/// the library. Loops; holds still with Reduce Motion on.
private struct ShareDemo: View {
    private enum Phase: CaseIterable {
        case post, sheet, tap, saved
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            screen(.tap)
        } else {
            PhaseAnimator(Phase.allCases) { phase in
                screen(phase)
            } animation: { phase in
                switch phase {
                case .post: .spring(duration: 0.5).delay(1.4)
                case .sheet: .spring(duration: 0.5, bounce: 0.15).delay(0.6)
                case .tap: .spring(duration: 0.35).delay(0.5)
                case .saved: .spring(duration: 0.6, bounce: 0.25).delay(0.2)
                }
            }
        }
    }

    private func screen(_ phase: Phase) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.background)
            post(phase)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(16)
            shareSheet(phase)
            savedToast(phase)
        }
        .frame(width: 250, height: 360)
        .clipShape(.rect(cornerRadius: 36, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 6)
        }
        .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
        .accessibilityElement()
        .accessibilityLabel("A post is shared to Snag and saved to your library.")
    }

    private func post(_ phase: Phase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(.secondary.opacity(0.5)).frame(width: 70, height: 7)
                    Capsule().fill(.secondary.opacity(0.25)).frame(width: 44, height: 6)
                }
            }
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.8, blue: 0.45), Color(red: 0.98, green: 0.42, blue: 0.45), Color(red: 0.5, green: 0.3, blue: 0.85)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 210)
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(12)
                }
            HStack(spacing: 14) {
                Image(systemName: "heart")
                Image(systemName: "bubble.right")
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(phase == .post ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .scaleEffect(phase == .post ? 1.15 : 1)
            }
            .font(.system(size: 16, weight: .semibold))
        }
        // Into the library: the post shrinks away toward the bottom.
        .scaleEffect(phase == .saved ? 0.25 : 1, anchor: .bottom)
        .opacity(phase == .saved ? 0 : 1)
        .offset(y: phase == .saved ? 80 : 0)
    }

    private func shareSheet(_ phase: Phase) -> some View {
        let isUp = phase == .sheet || phase == .tap
        return VStack(spacing: 12) {
            Capsule().fill(.tertiary).frame(width: 34, height: 5)
            HStack(alignment: .top, spacing: 14) {
                shareTarget(Image(systemName: "message.fill"), name: "Messages", color: .green)
                shareTarget(Image(systemName: "envelope.fill"), name: "Mail", color: .blue)
                VStack(spacing: 5) {
                    SnagMark(size: 46)
                        .scaleEffect(phase == .tap ? 0.88 : 1)
                        .overlay {
                            Circle()
                                .fill(.white.opacity(0.55))
                                .frame(width: 30, height: 30)
                                .opacity(phase == .tap ? 1 : 0)
                                .scaleEffect(phase == .tap ? 1 : 1.8)
                        }
                    Text("Snag").font(.system(size: 10, weight: .semibold))
                }
                shareTarget(Image(systemName: "ellipsis"), name: "More", color: .gray)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 28, style: .continuous))
        .padding(6)
        .offset(y: isUp ? 0 : 160)
    }

    private func shareTarget(_ icon: Image, name: String, color: Color) -> some View {
        VStack(spacing: 5) {
            icon
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(color.gradient, in: .rect(cornerRadius: 11, style: .continuous))
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func savedToast(_ phase: Phase) -> some View {
        Label("Saved to Snag", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .symbolRenderingMode(.multicolor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .scaleEffect(phase == .saved ? 1 : 0.6)
            .opacity(phase == .saved ? 1 : 0)
            .frame(maxHeight: .infinity)
    }
}

// MARK: - Notification preview

/// What the "Downloaded" notification looks like.
private struct NotificationPreview: View {
    @State private var isShown = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.multicolor)
                .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 2)), value: isShown)

            HStack(spacing: 12) {
                SnagMark(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Downloaded").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("now").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("3 items from your favorite account")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: 340)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .offset(y: isShown ? 0 : -20)
            .opacity(isShown ? 1 : 0)
        }
        .padding(.horizontal, 24)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.3).delay(0.3)) { isShown = true }
        }
        .accessibilityElement()
        .accessibilityLabel("A notification saying a post has downloaded.")
    }
}

#Preview {
    WelcomeView {}
}
#endif
