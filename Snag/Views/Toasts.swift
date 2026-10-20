import Observation
import SwiftUI

/// Short confirmations like "Saved to Photos", shown at the bottom of the window.
@Observable
final class Toasts {
    struct Toast: Equatable {
        var id = UUID()
        var message: String
        var systemImage: String
    }

    private(set) var current: Toast?

    func show(_ message: String, systemImage: String = "checkmark.circle.fill") {
        let toast = Toast(message: message, systemImage: systemImage)
        withAnimation(.snappy) { current = toast }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if current?.id == toast.id {
                withAnimation(.smooth) { current = nil }
            }
        }
    }
}

struct ToastOverlay: ViewModifier {
    var bottomPadding: CGFloat = 24
    @Environment(Toasts.self) private var toasts

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = toasts.current {
                Label(toast.message, systemImage: toast.systemImage)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .sensoryFeedback(.success, trigger: toasts.current?.id)
    }
}

extension View {
    func toastOverlay(bottomPadding: CGFloat = 24) -> some View { modifier(ToastOverlay(bottomPadding: bottomPadding)) }
}
