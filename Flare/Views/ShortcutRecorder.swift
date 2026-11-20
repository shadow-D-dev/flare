import AppKit

@MainActor
final class ShortcutRecorder: NSObject {
    private let alert = NSAlert()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let saveButton: NSButton
    private let apply: (LauncherShortcut) -> String?
    private var selection: LauncherShortcut?

    init(current: LauncherShortcut, apply: @escaping (LauncherShortcut) -> String?) {
        self.apply = apply
        saveButton = alert.addButton(withTitle: "Save")
        super.init()

        alert.messageText = "Launcher Shortcut"
        alert.informativeText = "Press a key with ⌘, ⌃, or ⌥, or press a function key."
        statusLabel.frame = NSRect(x: 0, y: 0, width: 310, height: 36)
        statusLabel.maximumNumberOfLines = 2
        alert.accessoryView = statusLabel
        statusLabel.stringValue = "Current shortcut is \(current.displayName)"

        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.isEnabled = false
        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1B}"
        cancelButton.keyEquivalentModifierMask = []
        let defaultButton = alert.addButton(withTitle: "Use Default")
        defaultButton.target = self
        defaultButton.action = #selector(useDefault)
    }

    func run() {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, alert.window.isKeyWindow else { return event }
            if let shortcut = LauncherShortcut(event: event) {
                if !event.isARepeat { select(shortcut) }
                return nil
            }
            return event
        }
        defer { if let monitor { NSEvent.removeMonitor(monitor) } }

        NSApp.activate()
        // Keep the recorder alive while AppKit uses its weak button targets.
        withExtendedLifetime(self) {
            _ = alert.runModal()
        }
    }

    @objc private func useDefault() {
        select(.optionSpace)
    }

    @objc private func save() {
        guard let selection else { return }
        if let message = apply(selection) {
            statusLabel.stringValue = message
            statusLabel.textColor = .systemRed
        } else {
            NSApp.stopModal(withCode: .OK)
        }
    }

    private func select(_ shortcut: LauncherShortcut) {
        selection = shortcut
        saveButton.isEnabled = true
        statusLabel.stringValue = shortcut.displayName
        statusLabel.textColor = .labelColor
    }
}
