#if os(iOS)
import SwiftUI

/// The sheet behind the + button: one field for the link, then Download.
struct AddLinkView: View {
    @Environment(LinkProcessor.self) private var processor
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var link: URL? { Site.firstLink(in: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add a Link")
                    .font(.title2.bold())
                Text("Paste a link to a post on Instagram, TikTok or X.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                field
                hint
            }

            Button(action: submit) {
                Label("Download", systemImage: "arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(link == nil)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { isFocused = true }
        .animation(.snappy, value: link)
        .animation(.snappy, value: text.isEmpty)
    }

    private var field: some View {
        HStack(spacing: 10) {
            Group {
                if let link {
                    SiteBadge(site: Site(url: link), size: 30)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "link")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 30, height: 30)

            TextField("instagram.com/p/…", text: $text)
                .focused($isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .textContentType(.URL)
                .submitLabel(.go)
                .onSubmit(submit)

            if text.isEmpty {
                // The system's paste button, so there's no "Allow Paste" prompt.
                PasteButton(payloadType: String.self) { strings in
                    text = strings.first ?? ""
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .tint(.accentColor)
                .transition(.opacity)
            } else {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
                .transition(.opacity)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 56)
        .background(.fill.tertiary, in: .capsule)
        .contentShape(.capsule)
        .onTapGesture { isFocused = true }
    }

    @ViewBuilder private var hint: some View {
        if let link {
            let site = Site(url: link)
            Text(site == .other ? "Link found" : "\(site.displayName) post")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
        } else if !text.isEmpty {
            Text("That doesn't look like a link.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.red)
                .padding(.leading, 16)
        } else {
            Text(" ").font(.footnote)
        }
    }

    private func submit() {
        guard let link else { return }
        processor.submit(link)
        dismiss()
    }
}
#endif
