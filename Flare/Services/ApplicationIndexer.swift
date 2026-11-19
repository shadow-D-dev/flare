import AppKit
import ImageIO

struct ApplicationIndex: Sendable {
    let searcher: ApplicationSearcher
    let icons: [URL: CGImage]
    let duplicateNames: Set<String>
    let bundledFrostedIcons: [String: CGImage]
}

enum ApplicationIndexer {
    static let iconSize: CGFloat = 28

    static func scan(excluding ownBundleURL: URL, roots: [URL] = defaultRoots) -> ApplicationIndex {
        let fileManager = FileManager.default
        var seenPaths: Set<String> = [ownBundleURL.resolvingSymlinksInPath().standardizedFileURL.path]
        var seenNames: Set<String> = []
        var duplicateNames: Set<String> = []
        var items: [ApplicationItem] = []
        var icons: [URL: CGImage] = [:]

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let entry as URL in enumerator {
                guard entry.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { continue }
                enumerator.skipDescendants()

                autoreleasepool {
                    let url = entry.resolvingSymlinksInPath().standardizedFileURL
                    let path = url.path
                    guard seenPaths.insert(path).inserted,
                          (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                          let bundle = Bundle(url: url),
                          let executable = bundle.executableURL,
                          fileManager.isExecutableFile(atPath: executable.path) else { return }

                    let name = ["CFBundleDisplayName", "CFBundleName"].lazy.compactMap { key in
                        (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    }.first { !$0.isEmpty } ?? url.deletingPathExtension().lastPathComponent

                    items.append(ApplicationItem(name: name, bundleIdentifier: bundle.bundleIdentifier, url: url))
                    icons[url] = applicationIcon(at: path)
                    if !seenNames.insert(name).inserted {
                        duplicateNames.insert(name)
                    }
                }
            }
        }

        return ApplicationIndex(
            searcher: ApplicationSearcher(items: items), icons: icons, duplicateNames: duplicateNames,
            bundledFrostedIcons: loadFrostedIcons(in: ownBundleURL)
        )
    }

    private static var defaultRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    private static func applicationIcon(at path: String) -> CGImage? {
        let icon = NSWorkspace.shared.icon(forFile: path)
        let pixels = Int(iconSize * 2)
        guard icon.isValid,
              let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        // Keep AppKit's icon object and drawing context on this worker. Only the small bitmap crosses to the UI.
        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = previousContext }

        context.interpolationQuality = .high
        icon.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()
    }

    private static func loadFrostedIcons(in appURL: URL) -> [String: CGImage] {
        guard let resources = Bundle(url: appURL)?.resourceURL,
              let files = try? FileManager.default.contentsOfDirectory(
                at: resources.appendingPathComponent("FrostedIcons", isDirectory: true),
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
              ) else { return [:] }

        var icons: [String: CGImage] = [:]
        for file in files where file.pathExtension == "png" {
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            icons[file.deletingPathExtension().lastPathComponent] = image
        }
        return icons
    }
}
