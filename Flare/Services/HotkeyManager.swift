import Carbon

@MainActor
final class HotkeyManager {
    struct Shortcut {
        let keyCode: UInt32
        let modifiers: UInt32

        static let optionSpace = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    }

    private let identifier = EventHotKeyID(signature: 0x464C4152, id: 1) // FLAR
    private var handler: EventHandlerRef?
    private var hotkey: EventHotKeyRef?
    private var onPress: (() -> Void)?
    private var isPressed = false

    func register(_ shortcut: Shortcut, onPress: @escaping () -> Void) -> OSStatus {
        unregister()

        let target = GetApplicationEventTarget()
        let events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let handlerStatus = InstallEventHandler(target, { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }

            var identifier = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
            )
            guard status == noErr else { return status }

            let manager = Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
            let signature = identifier.signature
            let id = identifier.id
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            // The application event target dispatches through the main event loop.
            return MainActor.assumeIsolated {
                manager.receive(signature: signature, id: id, pressed: pressed)
            }
        }, events.count, events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard handlerStatus == noErr else { return handlerStatus }

        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, identifier, target, UInt32(kEventHotKeyExclusive), &hotkey
        )
        if status == noErr {
            self.onPress = onPress
        } else {
            unregister()
        }
        return status
    }

    func unregister() {
        if let hotkey {
            UnregisterEventHotKey(hotkey)
            self.hotkey = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
        onPress = nil
        isPressed = false
    }

    private func receive(signature: OSType, id: UInt32, pressed: Bool) -> OSStatus {
        guard signature == identifier.signature, id == identifier.id else { return OSStatus(eventNotHandledErr) }

        let shouldInvoke = pressed && !isPressed
        isPressed = pressed
        if shouldInvoke {
            onPress?()
        }
        return noErr
    }
}
