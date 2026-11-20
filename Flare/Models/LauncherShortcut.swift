import AppKit
import Carbon

struct LauncherShortcut {
    private static let modifierKeys: [(flag: NSEvent.ModifierFlags, mask: UInt32, symbol: String)] = [
        (.control, UInt32(controlKey), "⌃"),
        (.option, UInt32(optionKey), "⌥"),
        (.shift, UInt32(shiftKey), "⇧"),
        (.command, UInt32(cmdKey), "⌘"),
    ]
    private static let requiredModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
    private static let modifierMask = modifierKeys.reduce(UInt32(0)) { $0 | $1.mask }

    static let optionSpace = LauncherShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), keyName: "Space")

    let keyCode: UInt32
    let modifiers: UInt32
    private let keyName: String

    var displayName: String {
        let symbols = Self.modifierKeys.filter { modifiers & $0.mask != 0 }.map(\.symbol).joined()
        return symbols.isEmpty ? keyName : "\(symbols) \(keyName)"
    }

    var preference: [String: Any] {
        ["keyCode": keyCode, "modifiers": modifiers, "keyName": keyName]
    }

    private init(keyCode: UInt32, modifiers: UInt32, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    init?(preference: [String: Any]) {
        guard let keyCode = preference["keyCode"] as? UInt32, keyCode <= UInt16.max,
              let modifiers = preference["modifiers"] as? UInt32, modifiers & ~Self.modifierMask == 0,
              let keyName = preference["keyName"] as? String, !keyName.isEmpty else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers, keyName: keyName)
    }

    init?(event: NSEvent) {
        let characters = [event.characters(byApplyingModifiers: []), event.charactersIgnoringModifiers]
            .compactMap { $0 }.first { !$0.isEmpty }
        let functionKey = event.charactersIgnoringModifiers?.unicodeScalars.first.flatMap { character -> Int? in
            let scalar = Int(character.value)
            guard (NSF1FunctionKey...NSF35FunctionKey).contains(scalar) else { return nil }
            return scalar - NSF1FunctionKey + 1
        }
        let flags = event.modifierFlags
        guard !flags.intersection(Self.requiredModifiers).isEmpty || functionKey != nil else { return nil }

        let modifiers = Self.modifierKeys.reduce(into: UInt32(0)) { mask, key in
            if flags.contains(key.flag) { mask |= key.mask }
        }
        let keyName = functionKey.map { "F\($0)" } ?? Self.name(for: event.keyCode, characters: characters)
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyName: keyName)
    }

    private static func name(for keyCode: UInt16, characters: String?) -> String {
        switch Int(keyCode) {
        case kVK_Space: "Space"
        case kVK_Return: "↩"
        case kVK_ANSI_KeypadEnter: "⌤"
        case kVK_Tab: "⇥"
        case kVK_Escape: "Esc"
        case kVK_Delete: "⌫"
        case kVK_ForwardDelete: "⌦"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_Home: "Home"
        case kVK_End: "End"
        case kVK_PageUp: "Page Up"
        case kVK_PageDown: "Page Down"
        default: characters?.uppercased() ?? "Key \(keyCode)"
        }
    }
}
