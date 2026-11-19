import Foundation
import XCTest

final class ApplicationSearcherTests: XCTestCase {
    func testExactNameRanksFirst() {
        XCTAssertEqual(matches("Safari", in: ["Safari Technology Preview", "Safari"]), ["Safari", "Safari Technology Preview"])
    }

    func testPrefix() {
        XCTAssertEqual(matches("saf", in: ["Notes", "Safari"]), ["Safari"])
        XCTAssertEqual(matches("term", in: ["Terminal", "Activity Monitor"]), ["Terminal"])
    }

    func testCaseInsensitiveSearch() {
        XCTAssertEqual(matches("tErMiNaL", in: ["Terminal"]), ["Terminal"])
    }

    func testSubstring() {
        XCTAssertEqual(matches("chr", in: ["Google Chrome", "Calculator"]), ["Google Chrome"])
        XCTAssertEqual(matches("dit", in: ["TextEdit", "Notes"]), ["TextEdit"])
    }

    func testWordPrefixesAndInitials() {
        XCTAssertEqual(matches("vis code", in: ["Visual Studio Code", "Voice Memos"]), ["Visual Studio Code"])
        XCTAssertEqual(matches("vsc", in: ["Visual Studio Code", "Music"]), ["Visual Studio Code"])
    }

    func testFuzzySubsequenceRequiresLetterOrder() {
        XCTAssertEqual(matches("fga", in: ["Figma", "Flag"]), ["Figma"])
        XCTAssertEqual(matches("agf", in: ["Figma"]), [])
    }

    func testRankOrder() {
        XCTAssertEqual(
            matches("code", in: ["Cobra Ode", "Compile Outline Debug Editor", "Decode", "Code Runner", "Code"]),
            ["Code", "Code Runner", "Decode", "Compile Outline Debug Editor", "Cobra Ode"]
        )
    }

    func testEmptyQueriesReturnAlphabeticalResultsWithinTheLimit() {
        let apps = ["Terminal", "Safari", "Pages", "Notes", "Music", "Mail", "Calendar", "Books"]
        let firstSeven = ["Books", "Calendar", "Mail", "Music", "Notes", "Pages", "Safari"]
        for query in ["", " \t\n ", "--"] {
            XCTAssertEqual(matches(query, in: apps), firstSeven)
        }
    }

    func testNoMatchesAndEmptyIndex() {
        XCTAssertEqual(matches("zzxyz", in: ["Safari", "Mail"]), [])
        XCTAssertEqual(matches("text", in: []), [])
        XCTAssertEqual(matches("", in: []), [])
    }

    func testUnicodeNamesAndDiacritics() {
        XCTAssertEqual(matches("CAFE deja vu", in: ["Café Déjà Vu"]), ["Café Déjà Vu"])
        XCTAssertEqual(matches("画像", in: ["Safari", "画像編集"]), ["画像編集"])
        XCTAssertEqual(matches("Ｃａｍｅｒａ", in: ["Camera"]), ["Camera"])
    }

    func testSpacesAndPunctuation() {
        XCTAssertEqual(matches("  visual--studio.code  ", in: ["Visual Studio Code"]), ["Visual Studio Code"])
        XCTAssertEqual(matches("musicmaker", in: ["Music-Maker"]), ["Music-Maker"])
    }

    func testDuplicateNamesAreKeptAndSortedByPath() {
        let userCopy = item("Firefox", path: "/Users/test/Applications/Firefox.app")
        let systemCopy = item("Firefox", path: "/Applications/Firefox.app")
        let browser = ApplicationSearcher(items: [userCopy, item("Firefox Developer Edition"), systemCopy])
        XCTAssertEqual(browser.search("firefox", limit: 2), [systemCopy, userCopy])
    }

    func testOrderingIsIndependentOfDiscoveryOrder() {
        let names = ["App Dock", "App Cube", "App Boat", "App Data"]
        let expected = ["App Boat", "App Cube", "App Data", "App Dock"]
        XCTAssertEqual(matches("App", in: names), expected)
        XCTAssertEqual(matches("App", in: names.reversed()), expected)
    }

    func testNonPositiveLimitsReturnNoResults() {
        let searcher = ApplicationSearcher(items: [item("Safari")])
        XCTAssertEqual(searcher.search("", limit: 0), [])
        XCTAssertEqual(searcher.search("saf", limit: -1), [])
    }

    private func matches(_ query: String, in names: [String]) -> [String] {
        ApplicationSearcher(items: names.map { item($0) }).search(query).map(\.name)
    }

    private func item(_ name: String, path: String? = nil) -> ApplicationItem {
        ApplicationItem(name: name, bundleIdentifier: nil, url: URL(fileURLWithPath: path ?? "/Applications/\(name).app"))
    }
}
