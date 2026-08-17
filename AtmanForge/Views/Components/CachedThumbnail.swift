import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Displays a thumbnail from `ThumbnailCache`, decoding on a background queue
/// on cache misses so scrolling through long lists never blocks the main thread.
struct CachedThumbnail: View {
    #if os(macOS)
    typealias PlatformImage = NSImage
    #else
    typealias PlatformImage = UIImage
    #endif

    let url: URL
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat = 4
    var maxPixelSize: CGFloat = 128
    var onHover: ((Bool) -> Void)?

    @State private var loadedImage: PlatformImage?
    @State private var loadFailed = false

    private var currentImage: PlatformImage? {
        ThumbnailCache.shared.cachedImage(for: url) ?? loadedImage
    }

    var body: some View {
        Group {
            if let image = currentImage {
                thumbImage(image)
                    .onHover { isHovered in onHover?(isHovered) }
            } else if loadFailed {
                Color.clear.frame(width: width, height: height)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(0.2))
            }
        }
        .frame(width: width, height: height)
        .task(id: url) {
            if ThumbnailCache.shared.cachedImage(for: url) != nil { return }
            loadedImage = nil
            loadFailed = false
            if let image = await ThumbnailCache.shared.imageAsync(for: url, maxPixelSize: maxPixelSize) {
                loadedImage = image
            } else {
                loadFailed = true
            }
        }
    }

    #if os(macOS)
    private func thumbImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    #else
    private func thumbImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    #endif
}
