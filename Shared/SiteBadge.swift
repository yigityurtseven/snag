import SwiftUI

/// The small mark that tells you where a post came from, in each site's own
/// logo and colors.
struct SiteBadge: View {
    let site: Site
    var size: CGFloat = 22

    var body: some View {
        logo
            .frame(width: size * 0.56, height: size * 0.56)
            .frame(width: size, height: size)
            .background(site.gradient, in: .circle)
            .accessibilityLabel(site.displayName)
    }

    @ViewBuilder private var logo: some View {
        switch site {
        case .instagram:
            InstagramGlyph().foregroundStyle(.white)
        case .tiktok:
            // TikTok's note, with its cyan and red echoes.
            let shift = max(size * 0.025, 0.5)
            ZStack {
                logoImage("TikTokLogo").foregroundStyle(Color(red: 0.15, green: 0.96, blue: 0.93)).offset(x: -shift, y: -shift)
                logoImage("TikTokLogo").foregroundStyle(Color(red: 1, green: 0.17, blue: 0.33)).offset(x: shift, y: shift)
                logoImage("TikTokLogo").foregroundStyle(.white)
            }
        case .x:
            logoImage("XLogo").foregroundStyle(.white).scaleEffect(0.9)
        case .other:
            Image(systemName: site.symbol)
                .resizable()
                .scaledToFit()
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
    }

    private func logoImage(_ name: String) -> some View {
        Image(name).resizable().renderingMode(.template).scaledToFit()
    }
}

/// Instagram's glyph: a rounded square, the lens and the flash.
struct InstagramGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = side * 0.095
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
                    .strokeBorder(lineWidth: line)
                Circle()
                    .strokeBorder(lineWidth: line)
                    .frame(width: side * 0.48, height: side * 0.48)
                Circle()
                    .frame(width: side * 0.12, height: side * 0.12)
                    .offset(x: side * 0.25, y: -side * 0.25)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

extension Site {
    var gradient: AnyShapeStyle {
        switch self {
        case .instagram:
            // Instagram's own: yellow at the bottom left through orange and pink to purple.
            AnyShapeStyle(EllipticalGradient(
                colors: [Color(red: 1, green: 0.84, blue: 0.36), Color(red: 0.98, green: 0.49, blue: 0.13),
                         Color(red: 0.87, green: 0.11, blue: 0.47), Color(red: 0.51, green: 0.2, blue: 0.83)],
                center: .bottomLeading, startRadiusFraction: 0, endRadiusFraction: 1.5))
        case .tiktok, .x:
            AnyShapeStyle(Color.black)
        case .other:
            AnyShapeStyle(LinearGradient(colors: [.gray, Color(white: 0.35)], startPoint: .top, endPoint: .bottom))
        }
    }
}
