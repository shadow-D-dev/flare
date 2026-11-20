import AppKit
import Carbon
import XCTest

final class LauncherShortcutTests: XCTestCase {
    func testModifiedKeyRetainsItsPhysicalKeyAndLabelAcrossPreferenceReload() throws {
        let event = try keyEvent(kVK_ANSI_K, modifiers: [.command, .shift, .capsLock], characters: "K")
        let shortcut = try XCTUnwrap(LauncherShortcut(event: event))
        let data = try PropertyListSerialization.data(fromPropertyList: shortcut.preference, format: .binary, options: 0)
        let preference = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let restored = try XCTUnwrap(LauncherShortcut(preference: preference))

        XCTAssertEqual(restored.keyCode, UInt32(kVK_ANSI_K))
        XCTAssertEqual(restored.modifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(restored.displayName, "⇧⌘ K")
    }

    func testFunctionKeyCanBeAssignedWithoutModifiers() throws {
        let character = String(try XCTUnwrap(UnicodeScalar(NSF1FunctionKey + 12)))
        let event = try keyEvent(kVK_F13, characters: character)
        let shortcut = try XCTUnwrap(LauncherShortcut(event: event))

        XCTAssertEqual(shortcut.keyCode, UInt32(kVK_F13))
        XCTAssertEqual(shortcut.modifiers, 0)
        XCTAssertEqual(shortcut.displayName, "F13")
    }

    func testOrdinaryTypingIsNotAnAssignableShortcut() throws {
        XCTAssertNil(LauncherShortcut(event: try keyEvent(kVK_ANSI_K, characters: "k")))
        XCTAssertNil(LauncherShortcut(event: try keyEvent(kVK_ANSI_K, modifiers: .shift, characters: "K")))
    }

    private func keyEvent(
        _ keyCode: Int, modifiers: NSEvent.ModifierFlags = [], characters: String
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(keyCode)
        ))
    }
}
