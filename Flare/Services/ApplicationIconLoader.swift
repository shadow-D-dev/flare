import AppKit
import ImageIO

actor ApplicationIconLoader {
    static let shared = ApplicationIconLoader()
    static let iconSize: CGFloat = 28
    private static let pixels = Int(iconSize * 2)

    func icon(for app: ApplicationItem, usesFrostedIcons: Bool, frostedIconFile: URL?) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        return autoreleasepool {
            if usesFrostedIcons, let frostedIconFile, let icon = Self.bundledIcon(at: frostedIconFile) {
                return icon
            }

            let original = Self.applicationIcon(at: app.url.path)
            if usesFrostedIcons {
                return FrostedIconRenderer.render(original, identifier: app.bundleIdentifier ?? app.name) ?? original
            }
            return original
        }
    }

    private static func applicationIcon(at path: String) -> CGImage? {
        let icon = NSWorkspace.shared.icon(forFile: path)
        guard icon.isValid,
              let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        // AppKit's icon and graphics context stay on the worker. Only the small bitmap crosses to the UI.
        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = previousContext }

        context.interpolationQuality = .high
        icon.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()
    }

    private static func bundledIcon(at file: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
