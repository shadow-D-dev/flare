import Foundation

struct ApplicationItem: Equatable, Sendable {
    let name: String
    let bundleIdentifier: String?
    let url: URL
    let alternateName: String?

    init(name: String, bundleIdentifier: String?, url: URL, alternateName: String? = nil) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.url = url
        self.alternateName = alternateName
    }
}
