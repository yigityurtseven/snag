import LinkPresentation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Receives a link from the share sheet and starts downloading it right away
/// (see `ShareDownloader`), so the post is saved without opening Snag. If that
/// can't start, the link waits in the inbox for the app instead.
///
/// Shown over the whole screen (NSExtensionActionWantsFullScreenPresentation)
/// and see-through, so the confirmation plays over the app being shared from.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let context = extensionContext
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let host = UIHostingController(rootView: ShareConfirmationView(providers: providers) { saved in
            if saved {
                context?.completeRequest(returningItems: nil)
            } else {
                context?.cancelRequest(withError: CocoaError(.featureUnsupported))
            }
        })
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    /// iOS 26 paints the views around an extension's view opaque, even for a
    /// full-screen one; clearing them lets the app being shared from show through.
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        var ancestor = view.superview
        while let current = ancestor {
            current.backgroundColor = .clear
            ancestor = current.superview
        }
    }
}

/// A card for the post drops in while the media is found, gets a checkmark
/// once it's downloading (or queued for the app), and falls away. Tapping
/// anywhere finishes early.
private struct ShareConfirmationView: View {
    let providers: [NSItemProvider]
    /// Called once the card has left, with whether a link was saved.
    let onFinish: (Bool) -> Void

    private enum Phase { case arriving, saved, failed, leaving }

    @State private var phase = Phase.arriving
    @State private var hasAppeared = false
    @State private var site = Site.other
    @State private var failure: String?
    /// The post, if its downloads started from here.
    @State private var downloading: MediaItem?
    @State private var preview: UIImage?
    @State private var finishTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(isShowing ? 0.45 : 0)
                    .contentShape(.rect)
                    .onTapGesture { if phase == .saved || phase == .failed { leave() } }

                glow(height: proxy.size.height)

                VStack(spacing: 28) {
                    Spacer(minLength: 0)
                    card
                    status
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, proxy.size.height * 0.08)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .animation(.spring(duration: 0.55, bounce: 0.3), value: phase)
        .animation(.spring(duration: 0.6, bounce: 0.3), value: hasAppeared)
        .sensoryFeedback(trigger: phase) { _, phase in
            switch phase {
            case .saved: .success
            case .failed: .error
            default: nil
            }
        }
        .task {
            hasAppeared = true
            await save()
        }
    }

    private var isShowing: Bool { hasAppeared && phase != .leaving }

    // MARK: Glow

    private func glow(height: CGFloat) -> some View {
        LinearGradient(colors: [.clear, .pink.opacity(0.55), .purple.opacity(0.7), .blue.opacity(0.6)],
                       startPoint: .top, endPoint: .bottom)
            .blur(radius: 40)
            .frame(height: height * 0.55)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .opacity(isShowing ? (phase == .arriving ? 0.7 : 1) : 0)
            .offset(y: isShowing ? 0 : height * 0.4)
            .allowsHitTesting(false)
    }

    // MARK: Card

    private var card: some View {
        let size = cardSize
        return cardContent
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) { badge }
            .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
            .rotationEffect(.degrees(phase == .arriving ? -4 : 0))
            .scaleEffect(hasAppeared ? (phase == .leaving ? 0.8 : phase == .failed ? 0.9 : 1) : 0.7)
            .offset(y: phase == .leaving ? 180 : (hasAppeared ? 0 : 120))
            .opacity(isShowing ? 1 : 0)
    }

    @ViewBuilder private var cardContent: some View {
        if let preview {
            Image(uiImage: preview).resizable().scaledToFill()
        } else {
            ZStack {
                Rectangle().fill(.regularMaterial)
                SiteBadge(site: site, size: 72)
            }
        }
    }

    /// The post's preview in its own shape, fitted in 240×300; square without one.
    private var cardSize: CGSize {
        guard let preview, preview.size.width > 0, preview.size.height > 0 else {
            return CGSize(width: 200, height: 200)
        }
        let ratio = preview.size.width / preview.size.height
        var size = CGSize(width: 240, height: 240 / ratio)
        if size.height > 300 { size = CGSize(width: 300 * ratio, height: 300) }
        return size
    }

    private var badge: some View {
        let shown = phase == .saved || phase == .failed
        return Image(systemName: phase == .failed ? "exclamationmark" : "checkmark")
            .font(.system(size: 20, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(phase == .failed ? Color.orange : Color.green))
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            .scaleEffect(shown ? 1 : 0.2)
            .opacity(shown ? 1 : 0)
            .offset(x: 14, y: -14)
            .animation(.spring(duration: 0.45, bounce: 0.55).delay(shown ? 0.1 : 0), value: shown)
    }

    // MARK: Status

    private var status: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2.weight(.bold))
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .opacity(isShowing ? 1 : 0)
    }

    private var title: String {
        switch phase {
        case .arriving: "Finding your post…"
        case .failed: "Couldn't Add"
        default: downloading == nil ? "Added to Snag" : "Downloading"
        }
    }

    private var subtitle: String {
        switch phase {
        case .failed: return failure ?? "No link found in what you shared."
        case .arriving: return " "
        default:
            if let downloading {
                let count = downloading.files.count
                return (count > 1 ? "\(count) items" : "Your \(site.displayName) post")
                    + " will be in Snag in a moment. You'll get a notification when it's saved."
            }
            return "Your \(site.displayName) post downloads when you open Snag."
        }
    }

    // MARK: Saving

    private func save() async {
        let started = Date.now
        guard let url = await Self.firstLink(in: providers) else {
            await show(.failed, after: started)
            return
        }
        site = Site(url: url)
        async let preview = Self.previewImage(for: url)
        do {
            if let item = await ShareDownloader.start(url) {
                downloading = item
            } else {
                try PendingLinks.enqueue(url)
            }
            await show(.saved, after: started)
        } catch {
            failure = error.localizedDescription
            await show(.failed, after: started)
        }
        if let image = await preview, phase != .leaving {
            withAnimation(.smooth(duration: 0.4)) { self.preview = image }
        }
    }

    /// Moves on once the card has had a moment, so a quick save still reads.
    private func show(_ next: Phase, after started: Date) async {
        let shown = Date.now.timeIntervalSince(started)
        if shown < 0.8 { try? await Task.sleep(for: .seconds(0.8 - shown)) }
        phase = next
        finishTask = Task {
            try? await Task.sleep(for: .seconds(next == .failed ? 2.6 : 2.2))
            guard !Task.isCancelled else { return }
            leave()
        }
    }

    private func leave() {
        finishTask?.cancel()
        guard phase != .leaving else { return }
        let saved = phase == .saved
        withAnimation(.spring(duration: 0.45, bounce: 0)) {
            phase = .leaving
        } completion: {
            onFinish(saved)
        }
    }

    // MARK: Reading what was shared

    private static func firstLink(in providers: [NSItemProvider]) async -> URL? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
               url.scheme?.hasPrefix("http") == true {
                return url
            }
        }
        // Some apps share the link as text, e.g. "Look at this! https://…".
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               let url = Site.firstLink(in: text) {
                return url
            }
        }
        return nil
    }

    /// The page's own preview image (a post's cover), if it has one.
    private static func previewImage(for url: URL) async -> UIImage? {
        let fetcher = LPMetadataProvider()
        fetcher.timeout = 4
        guard let metadata = try? await fetcher.startFetchingMetadata(for: url),
              let imageProvider = metadata.imageProvider else { return nil }
        return await withCheckedContinuation { continuation in
            _ = imageProvider.loadObject(ofClass: UIImage.self) { image, _ in
                continuation.resume(returning: image as? UIImage)
            }
        }
    }
}
