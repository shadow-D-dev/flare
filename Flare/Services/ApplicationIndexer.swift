import Foundation

struct ApplicationIndex: Sendable {
    let searcher: ApplicationSearcher
    let duplicateNames: Set<String>
    let frostedIconFiles: [String: URL]

    static let empty = ApplicationIndex(searcher: ApplicationSearcher(items: []), duplicateNames: [], frostedIconFiles: [:])
}

enum ApplicationIndexer {
    static func scan(excluding ownBundleURL: URL, roots: [URL] = defaultRoots) -> ApplicationIndex {
        let fileManager = FileManager.default
        var seenPaths: Set<String> = [ownBundleURL.resolvingSymlinksInPath().standardizedFileURL.path]
        var seenNames: Set<String> = []
        var duplicateNames: Set<String> = []
        var items: [ApplicationItem] = []

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

                    let filename = url.deletingPathExtension().lastPathComponent
                    let bundleName = ["CFBundleDisplayName", "CFBundleName"].lazy.compactMap { key in
                        (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    }.first { !$0.isEmpty } ?? filename
                    // Chromium web app bundles keep their original site name after a Finder rename.
                    let isChromiumWebApp = bundle.object(forInfoDictionaryKey: "CrAppModeShortcutID") is String
                    let name = isChromiumWebApp ? filename : bundleName

                    items.append(ApplicationItem(
                        name: name, bundleIdentifier: bundle.bundleIdentifier, url: url,
                        alternateName: name == bundleName ? nil : bundleName
                    ))
                    if !seenNames.insert(name).inserted {
                        duplicateNames.insert(name)
                    }
                }
            }
        }

        return ApplicationIndex(
            searcher: ApplicationSearcher(items: items), duplicateNames: duplicateNames,
            frostedIconFiles: findFrostedIconFiles(in: ownBundleURL)
        )
    }

    private static var defaultRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    private static func findFrostedIconFiles(in appURL: URL) -> [String: URL] {
        guard let resources = Bundle(url: appURL)?.resourceURL,
              let files = try? FileManager.default.contentsOfDirectory(
                at: resources.appendingPathComponent("FrostedIcons", isDirectory: true),
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
              ) else { return [:] }

        var icons: [String: URL] = [:]
        for file in files where file.pathExtension == "png" {
            icons[file.deletingPathExtension().lastPathComponent] = file
        }
        return icons
    }
}
