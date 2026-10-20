import QuickLookThumbnailing
import SwiftUI

/// A cropped thumbnail for an image or video file on disk, filling its frame.
struct MediaThumbnail: View {
    let url: URL
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { proxy in
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        }
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: 400, height: 400), scale: 2, representationTypes: .thumbnail
            )
            image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
        }
    }
}
