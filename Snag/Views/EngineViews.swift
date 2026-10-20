#if os(macOS)
import SwiftUI

/// Shown above the library until the engine is installed.
struct EngineBanner: View {
    @Environment(EngineInstaller.self) private var engine
    @Environment(LinkProcessor.self) private var processor

    var body: some View {
        switch engine.state {
        case .checking, .ready:
            EmptyView()
        case .notInstalled:
            banner(
                title: "Finish setting up Snag",
                message: "Snag needs to download its engine (Python, yt-dlp and gallery-dl, about a 30 MB download) once.",
                systemImage: "arrow.down.circle"
            ) {
                Button("Install") { install() }
                    .buttonStyle(.borderedProminent)
            }
        case .working(let step):
            banner(title: step, message: "This only happens once.", systemImage: nil) {
                EmptyView()
            }
        case .failed(let message):
            banner(title: "Engine setup failed", message: message, systemImage: "exclamationmark.triangle") {
                Button("Try Again") { install() }
            }
        }
    }

    private func install() {
        Task {
            await engine.install()
            if case .ready = engine.state { processor.retryFailed() }
        }
    }

    private func banner(
        title: String, message: String, systemImage: String?,
        @ViewBuilder action: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage).font(.title2).foregroundStyle(.tint)
            } else {
                ProgressView().controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            action()
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .padding([.horizontal, .top], 12)
    }
}

/// Snag › Settings: engine status and manual update.
struct EngineSettingsView: View {
    @Environment(EngineInstaller.self) private var engine
    @Environment(LinkProcessor.self) private var processor

    var body: some View {
        Form {
            LabeledContent("Engine") {
                switch engine.state {
                case .checking: Text("Checking…")
                case .notInstalled: Text("Not installed")
                case .working(let step): Text(step)
                case .ready(let versions): Text(versions).textSelection(.enabled)
                case .failed(let message): Text(message).foregroundStyle(.red)
                }
            }
            HStack {
                if engine.isInstalled {
                    Button("Update Now") { Task { await engine.update() } }
                    Button("Reinstall") { Task { await engine.install() } }
                } else {
                    Button("Install") {
                        Task {
                            await engine.install()
                            if case .ready = engine.state { processor.retryFailed() }
                        }
                    }
                }
            }
            .disabled(engine.isWorking)
            Text("yt-dlp and gallery-dl are updated automatically once a day.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
