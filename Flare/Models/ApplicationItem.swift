import Foundation

struct ApplicationItem: Equatable, Sendable {
    let name: String
    let bundleIdentifier: String?
    let url: URL
}
