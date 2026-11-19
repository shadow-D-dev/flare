import AppKit

final class LauncherPanel: NSPanel {
    var onCancel: (() -> Void)?
    private let acceptsKeyboard: Bool

    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }

    init(size: NSSize, acceptsKeyboard: Bool = true) {
        self.acceptsKeyboard = acceptsKeyboard
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        title = acceptsKeyboard ? "Flare" : ""
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllApplications, .ignoresCycle]
        if acceptsKeyboard { collectionBehavior.insert(.canJoinAllSpaces) }
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = !acceptsKeyboard
        animationBehavior = .none
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
