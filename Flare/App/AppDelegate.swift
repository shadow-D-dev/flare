import AppKit
import Carbon
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Appearance: String {
        case system, light, dark

        var appKitAppearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    private static let appearancePreferenceKey = "LauncherAppearance"
    private static let frostedIconsPreferenceKey = "FrostedIconsEnabled"

    private let launcher = LauncherWindowController()
    private let hotkey = HotkeyManager()
    private let logger = Logger(subsystem: "com.flarelauncher.Flare", category: "Hotkey")
    private let scanQueue = DispatchQueue(label: "com.flarelauncher.Flare.discovery", qos: .userInitiated, autoreleaseFrequency: .workItem)
    private let refreshItem = NSMenuItem(title: "Refresh Applications", action: nil, keyEquivalent: "")
    private let darkModeSwitch = NSSwitch()
    private let frostedIconsSwitch = NSSwitch()
    private var statusItem: NSStatusItem?

    private var isDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appearance = UserDefaults.standard.string(forKey: Self.appearancePreferenceKey)
            .flatMap(Appearance.init(rawValue:)) ?? .system
        NSApp.appearance = appearance.appKitAppearance
        UserDefaults.standard.register(defaults: [Self.frostedIconsPreferenceKey: true])
        launcher.usesFrostedIcons = UserDefaults.standard.bool(forKey: Self.frostedIconsPreferenceKey)

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
        darkModeSwitch.state = isDarkMode ? .on : .off
        frostedIconsSwitch.state = launcher.usesFrostedIcons ? .on : .off
        menu.addItem(switchMenuItem("Dark Mode", control: darkModeSwitch, action: #selector(toggleDarkMode(_:))))
        menu.addItem(switchMenuItem("Frosted Icons", control: frostedIconsSwitch, action: #selector(toggleFrostedIcons(_:))))
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
        launcher.dismiss(animated: false)
    }

    func menuWillOpen(_ menu: NSMenu) {
        launcher.dismiss()
        darkModeSwitch.state = isDarkMode ? .on : .off
    }

    @objc private func openFlare() {
        launcher.present()
    }

    private func switchMenuItem(_ title: String, control: NSSwitch, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self

        let row = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 30))
        row.autoresizingMask = [.width]
        let label = NSTextField(labelWithString: item.title)
        label.font = .menuFont(ofSize: 0)

        control.controlSize = .small
        control.target = self
        control.action = action
        control.setAccessibilityLabel(title)

        label.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        row.addSubview(control)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        item.view = row
        return item
    }

    @objc private func toggleDarkMode(_ sender: Any?) {
        let dark = (sender as? NSSwitch).map { $0.state == .on } ?? !isDarkMode
        let appearance: Appearance = dark ? .dark : .light
        UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearancePreferenceKey)
        NSApp.appearance = appearance.appKitAppearance
        darkModeSwitch.state = dark ? .on : .off
    }

    @objc private func toggleFrostedIcons(_ sender: Any?) {
        let enabled = (sender as? NSSwitch).map { $0.state == .on } ?? !launcher.usesFrostedIcons
        launcher.usesFrostedIcons = enabled
        frostedIconsSwitch.state = enabled ? .on : .off
        UserDefaults.standard.set(enabled, forKey: Self.frostedIconsPreferenceKey)
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
