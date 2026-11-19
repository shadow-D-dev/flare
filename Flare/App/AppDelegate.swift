import AppKit
import Carbon
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let launcher = LauncherWindowController()
    private let hotkey = HotkeyManager()
    private let logger = Logger(subsystem: "com.flarelauncher.Flare", category: "Hotkey")
    private let scanQueue = DispatchQueue(label: "com.flarelauncher.Flare.discovery", qos: .userInitiated, autoreleaseFrequency: .workItem)
    private let refreshItem = NSMenuItem(title: "Refresh Applications", action: nil, keyEquivalent: "")
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hotkeyStatus = hotkey.register(.optionSpace) { [weak self] in
            guard let self else { return }
            if launcher.isPresented {
                launcher.dismiss()
            } else {
                launcher.present()
            }
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Flare")
            symbol?.isTemplate = true
            button.image = symbol
            button.toolTip = "Flare"
            button.setAccessibilityLabel("Flare")
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let openItem = NSMenuItem(title: "Open Flare", action: #selector(openFlare), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        if hotkeyStatus == noErr {
            openItem.keyEquivalent = " "
            openItem.keyEquivalentModifierMask = .option
        } else {
            let title = hotkeyStatus == eventHotKeyExistsErr ? "⌥ Space is already in use" : "⌥ Space shortcut unavailable"
            let notice = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            notice.isEnabled = false
            menu.addItem(notice)
            logger.error("Could not register the global shortcut (OSStatus \(hotkeyStatus)).")
        }
        refreshItem.target = self
        refreshItem.action = #selector(refreshApplications)
        menu.addItem(refreshItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Flare", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
        refreshApplications()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launcher.present()
        return false
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        launcher.screenParametersDidChange()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey.unregister()
        launcher.dismiss()
    }

    func menuWillOpen(_ menu: NSMenu) {
        launcher.dismiss()
    }

    @objc private func openFlare() {
        launcher.present()
    }

    @objc private func refreshApplications() {
        guard refreshItem.isEnabled else { return }
        refreshItem.isEnabled = false
        refreshItem.title = "Refreshing Applications…"
        launcher.indexWillRefresh()

        let bundleURL = Bundle.main.bundleURL
        scanQueue.async { [weak self] in
            let index = ApplicationIndexer.scan(excluding: bundleURL)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                launcher.replaceIndex(index)
                refreshItem.title = "Refresh Applications"
                refreshItem.isEnabled = true
            }
        }
    }
}
