import SwiftUI

/// The app icon, drawn in SwiftUI for use inside the app (an app can't load
/// its own .icon). Same picture as Snag/AppIcon.icon: two photo cards and the
/// arrow that snags them, on coral.
struct SnagMark: View {
    var size: CGFloat = 60

    private var unit: CGFloat { size / 1024 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.52, blue: 0.4), Color(red: 0.91, green: 0.2, blue: 0.29)],
                                     startPoint: .top, endPoint: .bottom))
            card(photo: [Color(red: 1, green: 0.82, blue: 0.48), Color(red: 1, green: 0.54, blue: 0.36)], paper: Color(red: 1, green: 0.97, blue: 0.95))
                .rotationEffect(.degrees(-12))
                .offset(x: (445 - 512) * unit, y: (500 - 512) * unit)
            card(photo: [Color(red: 0.48, green: 0.38, blue: 1), Color(red: 1, green: 0.44, blue: 0.63)], paper: .white)
                .rotationEffect(.degrees(8))
                .offset(x: (585 - 512) * unit, y: (470 - 512) * unit)
            ZStack {
                Circle().fill(.white)
                Image(systemName: "arrow.down")
                    .font(.system(size: 150 * unit, weight: .heavy))
                    .foregroundStyle(Color(red: 0.98, green: 0.35, blue: 0.29))
            }
            .frame(width: 284 * unit, height: 284 * unit)
            .shadow(color: .black.opacity(0.15), radius: 12 * unit, y: 6 * unit)
            .offset(x: (690 - 512) * unit, y: (716 - 512) * unit)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func card(photo: [Color], paper: Color) -> some View {
        RoundedRectangle(cornerRadius: 46 * unit, style: .continuous)
            .fill(paper)
            .frame(width: 360 * unit, height: 470 * unit)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 26 * unit, style: .continuous)
                    .fill(LinearGradient(colors: photo, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 300 * unit, height: 330 * unit)
                    .padding(.top, 30 * unit)
            }
            .shadow(color: .black.opacity(0.12), radius: 10 * unit, y: 6 * unit)
    }
}

#Preview {
    HStack(spacing: 20) {
        SnagMark(size: 120)
        SnagMark(size: 60)
        SnagMark(size: 30)
    }
    .padding()
}
