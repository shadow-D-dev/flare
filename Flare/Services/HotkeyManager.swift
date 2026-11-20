import Carbon

@MainActor
final class HotkeyManager {
    private struct Registration {
        let shortcut: LauncherShortcut
        let ref: EventHotKeyRef
        let id: UInt32
    }

    private let signature: OSType = 0x464C4152 // FLAR
    private let onPress: () -> Void
    private var handler: EventHandlerRef?
    private var registration: Registration?
    private var nextID: UInt32 = 0
    private var isPressed = false

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
    }

    func register(_ shortcut: LauncherShortcut) -> OSStatus {
        if let current = registration?.shortcut,
           current.keyCode == shortcut.keyCode, current.modifiers == shortcut.modifiers {
            return noErr
        }
        let target = GetApplicationEventTarget()
        if handler == nil {
            let status = installHandler(on: target)
            guard status == noErr else { return status }
        }

        // Keep the current shortcut registered until the replacement succeeds.
        nextID &+= 1
        let identifier = EventHotKeyID(signature: signature, id: nextID)
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, identifier, target, UInt32(kEventHotKeyExclusive), &replacement
        )
        guard status == noErr, let replacement else {
            if registration == nil { unregister() }
            return status == noErr ? OSStatus(paramErr) : status
        }
        if let registration {
            let status = UnregisterEventHotKey(registration.ref)
            guard status == noErr else {
                UnregisterEventHotKey(replacement)
                return status
            }
        }
        registration = Registration(shortcut: shortcut, ref: replacement, id: identifier.id)
        isPressed = false
        return noErr
    }

    private func installHandler(on target: EventTargetRef?) -> OSStatus {
        let events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        return InstallEventHandler(target, { _, event, context in
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
    }

    func unregister() {
        if let registration {
            UnregisterEventHotKey(registration.ref)
            self.registration = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
        isPressed = false
    }

    private func receive(signature: OSType, id: UInt32, pressed: Bool) -> OSStatus {
        guard signature == self.signature, id == registration?.id else { return OSStatus(eventNotHandledErr) }

        let shouldInvoke = pressed && !isPressed
        isPressed = pressed
        if shouldInvoke {
            onPress()
        }
        return noErr
    }
}
