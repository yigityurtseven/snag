import SwiftUI

/// A photo you can pinch or double-tap to zoom, then pan around, like Photos.
/// Reports whether it's zoomed, so the carousel can stop paging meanwhile.
struct ZoomableImage: View {
    let url: URL
    let onTap: () -> Void
    let onZoomChange: (Bool) -> Void

    var body: some View {
        #if os(iOS)
        ZoomingScrollView(url: url, onTap: onTap, onZoomChange: onZoomChange)
            .ignoresSafeArea()
        #else
        MagnifyingImage(url: url, onTap: onTap, onZoomChange: onZoomChange)
        #endif
    }
}

#if os(iOS)
import UIKit

/// UIScrollView does zooming properly: rubber-banding, panning to the edges,
/// zooming toward your fingers.
private struct ZoomingScrollView: UIViewRepresentable {
    let url: URL
    let onTap: () -> Void
    let onZoomChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> CenteringScrollView {
        let scrollView = CenteringScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.backgroundColor = .clear

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTapped))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        context.coordinator.load(url, into: scrollView)
        return scrollView
    }

    func updateUIView(_ scrollView: CenteringScrollView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onZoomChange = onZoomChange
        if context.coordinator.url != url { context.coordinator.load(url, into: scrollView) }
    }

    static func dismantleUIView(_ scrollView: CenteringScrollView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var url: URL?
        var onTap: () -> Void = {}
        var onZoomChange: (Bool) -> Void = { _ in }
        var loadTask: Task<Void, Never>?
        private var isZoomed = false

        func load(_ url: URL, into scrollView: CenteringScrollView) {
            self.url = url
            loadTask?.cancel()
            loadTask = Task {
                let image = await Task.detached(priority: .userInitiated) {
                    UIImage(contentsOfFile: url.path(percentEncoded: false))?.preparingForDisplay()
                }.value
                guard !Task.isCancelled else { return }
                scrollView.setImage(image)
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? CenteringScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let zoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
            guard zoomed != isZoomed else { return }
            isZoomed = zoomed
            onZoomChange(zoomed)
        }

        @objc func singleTapped() { onTap() }

        /// Zooms in on the tapped point, or back out.
        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? CenteringScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }
            let scale = min(2.5, scrollView.maximumZoomScale)
            let point = gesture.location(in: scrollView.imageView)
            let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
            scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
        }
    }
}

/// Fits the image to the screen and keeps it centered while zoomed out.
final class CenteringScrollView: UIScrollView {
    let imageView = UIImageView()
    private var fittedForSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: UIImage?) {
        imageView.image = image
        fittedForSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Refit when the image arrives or the screen rotates.
        if bounds.size != fittedForSize, let image = imageView.image, image.size.width > 0, image.size.height > 0 {
            fittedForSize = bounds.size
            zoomScale = minimumZoomScale
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            imageView.frame = CGRect(origin: .zero, size: size)
            contentSize = size
        }
        let x = max((bounds.width - imageView.frame.width) / 2, 0)
        let y = max((bounds.height - imageView.frame.height) / 2, 0)
        imageView.frame.origin = CGPoint(x: x, y: y)
    }
}

#else

/// Pinch or double-click to zoom, drag to pan.
private struct MagnifyingImage: View {
    let url: URL
    let onTap: () -> Void
    let onZoomChange: (Bool) -> Void

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var baseOffset = CGSize.zero

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
        } placeholder: {
            ProgressView().tint(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .clipped()
        .gesture(
            MagnifyGesture()
                .onChanged { scale = max(1, min(baseScale * $0.magnification, 5)) }
                .onEnded { _ in settle() }
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { drag in
                    guard scale > 1 else { return }
                    offset = CGSize(width: baseOffset.width + drag.translation.width,
                                    height: baseOffset.height + drag.translation.height)
                }
                .onEnded { _ in baseOffset = offset },
            isEnabled: scale > 1
        )
        .onTapGesture(count: 2) {
            withAnimation(.snappy) { scale = scale > 1 ? 1 : 2.5 }
            settle()
        }
        .onTapGesture(perform: onTap)
        .onChange(of: scale > 1) { _, zoomed in onZoomChange(zoomed) }
    }

    private func settle() {
        baseScale = scale
        if scale <= 1 {
            withAnimation(.snappy) { offset = .zero }
            baseOffset = .zero
        }
    }
}

#endif
