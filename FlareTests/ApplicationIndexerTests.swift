import Foundation
import XCTest

final class ApplicationIndexerTests: XCTestCase {
    func testRenamedWebAppIsSearchableByInstalledAndOriginalNames() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let webApp = root.appendingPathComponent("Chromium Apps.localized/shadow.app", isDirectory: true)
        let nativeApp = root.appendingPathComponent("Instagram Native.app", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        try makeApp(at: webApp, displayName: "Instagram", bundleIdentifier: "test.browser.webapp", isWebApp: true)
        try makeApp(at: nativeApp, displayName: "Instagram", bundleIdentifier: "test.native")

        let index = ApplicationIndexer.scan(excluding: root.appendingPathComponent("Flare.app"), roots: [root])
        let shadow = ApplicationItem(
            name: "shadow", bundleIdentifier: "test.browser.webapp",
            url: webApp.resolvingSymlinksInPath(), alternateName: "Instagram"
        )
        let native = ApplicationItem(
            name: "Instagram", bundleIdentifier: "test.native", url: nativeApp.resolvingSymlinksInPath()
        )

        XCTAssertEqual(index.searcher.search("shadow"), [shadow])
        XCTAssertEqual(index.searcher.search("instagram"), [native, shadow])
        XCTAssertEqual(index.searcher.search("insta"), [native, shadow])
        XCTAssertEqual(index.searcher.search(""), [native, shadow])
        XCTAssertTrue(index.duplicateNames.isEmpty)
    }

    private func makeApp(at url: URL, displayName: String, bundleIdentifier: String, isWebApp: Bool = false) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let executableDirectory = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)

        var info = [
            "CFBundleDisplayName": displayName,
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "launcher",
        ]
        if isWebApp {
            info["CrAppModeShortcutID"] = "example"
        }
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))

        let executable = executableDirectory.appendingPathComponent("launcher")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }
}
