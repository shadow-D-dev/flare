import CoreGraphics

enum FrostedIconRenderer {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let pixels = Int(ApplicationIndexer.iconSize * 2)
    private static let palette: [(CGFloat, CGFloat, CGFloat)] = [
        (0.12, 0.64, 0.88), (0.50, 0.32, 0.79), (0.89, 0.24, 0.53),
        (0.19, 0.72, 0.49), (0.93, 0.48, 0.21), (0.28, 0.43, 0.87), (0.12, 0.67, 0.69)
    ]

    static func render(_ artwork: CGImage?, identifier: String) -> CGImage? {
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return nil }

        let canvas = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        let front = canvas.insetBy(dx: 4, dy: 4).offsetBy(dx: -3.5, dy: 2.5)
        let back = front.offsetBy(dx: 7, dy: -5)
        context.interpolationQuality = .high

        if let artwork {
            context.draw(artwork, in: canvas)
        }
        let (hasArtwork, accent) = sampleArtwork(in: context, identifier: identifier)
        context.clear(canvas)

        // Follow the app's silhouette on both layers so icons retain their individual shapes.
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        draw(hasArtwork ? artwork : nil, in: back, context: context)
        context.setBlendMode(.sourceIn)
        context.setFillColor(accent)
        context.fill(back.insetBy(dx: -1, dy: -1))
        context.endTransparencyLayer()
        context.restoreGState()

        context.beginTransparencyLayer(auxiliaryInfo: nil)
        draw(hasArtwork ? artwork : nil, in: front, context: context)
        context.setBlendMode(.sourceAtop)
        let highlight = CGColor(gray: 1, alpha: 0.48)
        let tint = accent.copy(alpha: 0.33) ?? accent
        if let glaze = CGGradient(colorsSpace: colorSpace, colors: [highlight, tint] as CFArray, locations: nil) {
            context.drawLinearGradient(
                glaze, start: CGPoint(x: front.minX, y: front.maxY),
                end: CGPoint(x: front.maxX, y: front.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        context.endTransparencyLayer()
        return context.makeImage()
    }

    private static func draw(_ artwork: CGImage?, in frame: CGRect, context: CGContext) {
        if let artwork {
            context.draw(artwork, in: frame)
            return
        }

        let tile = frame.insetBy(dx: 4, dy: 4)
        context.setFillColor(gray: 0.88, alpha: 1)
        context.addPath(CGPath(roundedRect: tile, cornerWidth: 11, cornerHeight: 11, transform: nil))
        context.fillPath()
        let window = tile.insetBy(dx: 9, dy: 12)
        context.setFillColor(gray: 0.35, alpha: 0.8)
        context.addPath(CGPath(roundedRect: window, cornerWidth: 3, cornerHeight: 3, transform: nil))
        context.fillPath()
        context.setFillColor(gray: 1, alpha: 0.85)
        context.fill(CGRect(x: window.minX + 1, y: window.maxY - 5, width: window.width - 2, height: 1))
    }

    private static func sampleArtwork(in context: CGContext, identifier: String) -> (Bool, CGColor) {
        let hash = identifier.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        let (red, green, blue) = palette[Int(hash % UInt32(palette.count))]
        let fallback = CGColor(red: red, green: green, blue: blue, alpha: 1)
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return (false, fallback) }

        var hasArtwork = false
        var totalWeight = 0.0
        var channels = SIMD3<Double>.zero
        for y in stride(from: 0, to: pixels, by: 2) {
            for x in stride(from: 0, to: pixels, by: 2) {
                let offset = y * context.bytesPerRow + x * 4
                let alpha = bytes[offset + 3]
                hasArtwork = hasArtwork || alpha > 0
                guard alpha > 144 else { continue }
                let rgb = SIMD3(
                    Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2])
                ) / Double(alpha)
                let chroma = rgb.max() - rgb.min()
                guard chroma > 0.14 else { continue }
                let weight = chroma * chroma
                channels += rgb * weight
                totalWeight += weight
            }
        }

        guard totalWeight > 1 else { return (hasArtwork, fallback) }
        let average = channels / totalWeight
        let spread = average.max() - average.min()
        guard spread > 0.12 else { return (hasArtwork, fallback) }
        let accent = (average - average.min()) * (0.75 / spread) + 0.16
        return (hasArtwork, CGColor(red: CGFloat(accent.x), green: CGFloat(accent.y), blue: CGFloat(accent.z), alpha: 1))
    }
}
