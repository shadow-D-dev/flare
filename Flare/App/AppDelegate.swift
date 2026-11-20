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
    private static let shortcutPreferenceKey = "LauncherShortcut"

    private var launcher: LauncherWindowController?
    private var applicationIndex = ApplicationIndex.empty
    private var usesFrostedIcons = true
    private lazy var hotkey = HotkeyManager { [weak self] in self?.toggleLauncher() }
    private let logger = Logger(subsystem: "com.flarelauncher.Flare", category: "Hotkey")
    private let scanQueue = DispatchQueue(label: "com.flarelauncher.Flare.discovery", qos: .userInitiated, autoreleaseFrequency: .workItem)
    private let refreshItem = NSMenuItem(title: "Refresh Applications", action: nil, keyEquivalent: "")
    private let shortcutItem = NSMenuItem(title: "Launcher Shortcut…", action: nil, keyEquivalent: "")
    private let shortcutNotice = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let darkModeSwitch = NSSwitch()
    private let frostedIconsSwitch = NSSwitch()
    private var statusItem: NSStatusItem?
    private var shortcut = LauncherShortcut.optionSpace
    private var isRecordingShortcut = false

    private var isDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appearance = UserDefaults.standard.string(forKey: Self.appearancePreferenceKey)
            .flatMap(Appearance.init(rawValue:)) ?? .system
        NSApp.appearance = appearance.appKitAppearance
        UserDefaults.standard.register(defaults: [Self.frostedIconsPreferenceKey: true])
        usesFrostedIcons = UserDefaults.standard.bool(forKey: Self.frostedIconsPreferenceKey)

        shortcut = UserDefaults.standard.dictionary(forKey: Self.shortcutPreferenceKey)
            .flatMap(LauncherShortcut.init(preference:)) ?? .optionSpace
        updateShortcutMenu(error: registerShortcut(shortcut))

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
        shortcutNotice.isEnabled = false
        menu.addItem(shortcutNotice)
        shortcutItem.target = self
        shortcutItem.action = #selector(changeLauncherShortcut)
        menu.addItem(shortcutItem)
        refreshItem.target = self
        refreshItem.action = #selector(refreshApplications)
        menu.addItem(refreshItem)
        darkModeSwitch.state = isDarkMode ? .on : .off
        frostedIconsSwitch.state = usesFrostedIcons ? .on : .off
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
        openFlare()
        return false
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        launcher?.screenParametersDidChange()
    }

    func applicationDidHide(_ notification: Notification) {
        launcher?.dismiss(animated: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey.unregister()
        launcher?.dismiss(animated: false)
    }

    func menuWillOpen(_ menu: NSMenu) {
        launcher?.dismiss()
        darkModeSwitch.state = isDarkMode ? .on : .off
    }

    @objc private func openFlare() {
        guard !isRecordingShortcut, launcher?.isPresented != true else { return }
        launcher?.dismiss(animated: false)

        let launcher = LauncherWindowController(
            index: applicationIndex, isRefreshing: !refreshItem.isEnabled, usesFrostedIcons: usesFrostedIcons
        ) { [weak self] dismissedLauncher in
            guard let self, self.launcher === dismissedLauncher else { return }
            self.launcher = nil
        }
        self.launcher = launcher
        launcher.present()
    }

    private func toggleLauncher() {
        guard !isRecordingShortcut else { return }
        if let launcher, launcher.isPresented {
            launcher.dismiss()
        } else {
            openFlare()
        }
    }

    @objc private func changeLauncherShortcut() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        defer { isRecordingShortcut = false }

        ShortcutRecorder(current: shortcut) { newShortcut in
            if let error = self.registerShortcut(newShortcut) { return error }
            self.shortcut = newShortcut
            UserDefaults.standard.set(newShortcut.preference, forKey: Self.shortcutPreferenceKey)
            self.updateShortcutMenu(error: nil)
            return nil
        }.run()
    }

    private func registerShortcut(_ shortcut: LauncherShortcut) -> String? {
        let status = hotkey.register(shortcut)
        guard status != noErr else { return nil }
        logger.error("Could not register the global shortcut (OSStatus \(status)).")
        if status == eventHotKeyExistsErr {
            return "\(shortcut.displayName) is already in use."
        }
        return "\(shortcut.displayName) couldn’t be registered."
    }

    private func updateShortcutMenu(error: String?) {
        shortcutItem.title = "Launcher Shortcut (\(shortcut.displayName))…"
        shortcutNotice.title = error ?? ""
        shortcutNotice.isHidden = error == nil
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
        let enabled = (sender as? NSSwitch).map { $0.state == .on } ?? !usesFrostedIcons
        usesFrostedIcons = enabled
        launcher?.usesFrostedIcons = enabled
        frostedIconsSwitch.state = enabled ? .on : .off
        UserDefaults.standard.set(enabled, forKey: Self.frostedIconsPreferenceKey)
    }

    @objc private func refreshApplications() {
        guard refreshItem.isEnabled else { return }
        refreshItem.isEnabled = false
        refreshItem.title = "Refreshing Applications…"
        launcher?.indexWillRefresh()

        let bundleURL = Bundle.main.bundleURL
        scanQueue.async { [weak self] in
            let index = ApplicationIndexer.scan(excluding: bundleURL)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                applicationIndex = index
                launcher?.replaceIndex(index)
                refreshItem.title = "Refresh Applications"
                refreshItem.isEnabled = true
            }
        }
    }
}
