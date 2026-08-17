import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import ImageIO

/// Shared in-memory cache for thumbnail images, using CGImageSource for efficient
/// downsampled loading (decodes at target size rather than full file resolution).
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    #if os(macOS)
    private let cache = NSCache<NSURL, NSImage>()
    #else
    private let cache = NSCache<NSURL, UIImage>()
    #endif

    private init() {
        cache.countLimit = 500
    }

    /// Returns the cached image without touching disk, so callers can render
    /// warm thumbnails synchronously and fall back to async loading on a miss.
    #if os(macOS)
    func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }
    #else
    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }
    #endif

    /// Loads and downsamples the image on a background queue, returning the
    /// cached copy on the main actor when ready.
    #if os(macOS)
    @MainActor
    func imageAsync(for url: URL, maxPixelSize: CGFloat = 128) async -> NSImage? {
        if let cached = cachedImage(for: url) { return cached }
        let cgImage = await Self.decodeCGImage(at: url, maxPixelSize: maxPixelSize)
        guard let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
    #else
    @MainActor
    func imageAsync(for url: URL, maxPixelSize: CGFloat = 128) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        let cgImage = await Self.decodeCGImage(at: url, maxPixelSize: maxPixelSize)
        guard let cgImage else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
    #endif

    private static func decodeCGImage(at url: URL, maxPixelSize: CGFloat) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
    }

    func invalidate(url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    func clearAll() {
        cache.removeAllObjects()
    }
}
