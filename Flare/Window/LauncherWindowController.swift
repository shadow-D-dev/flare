import AppKit
import OSLog

@MainActor
final class LauncherWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static let width: CGFloat = 680
    private static let searchHeight: CGFloat = 64
    private static let listInset: CGFloat = 8
    private static let rowHeight: CGFloat = 42
    private static let resultLimit = 7
    private static let emptyMessageHeight: CGFloat = 45
    private static let errorMessageHeight: CGFloat = 25

    private let panel = LauncherPanel(size: NSSize(width: width, height: searchHeight + 1 + emptyMessageHeight))
    private let motion = LauncherMotion(headerHeight: searchHeight)
    private let searchField = NSTextField()
    private let divider = NSBox()
    private let scrollView = NSScrollView()
    private let table = ApplicationsTableView()
    private let messageArea = NSView()
    private let messageLabel = NSTextField(labelWithString: "")
    private let fallbackIcon = NSImage(systemSymbolName: "app", accessibilityDescription: nil)
    private let logger = Logger(subsystem: "com.flarelauncher.Flare", category: "Launch")
    private lazy var listTop = scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor)
    private lazy var listBottom = messageArea.topAnchor.constraint(equalTo: scrollView.bottomAnchor)
    private lazy var messageHeight = messageArea.heightAnchor.constraint(equalToConstant: Self.emptyMessageHeight)
    private var contentHeight = searchHeight + 1 + emptyMessageHeight

    private var index: ApplicationIndex
    private let rowIcons = NSCache<NSURL, NSImage>()
    private var iconTask: Task<Void, Never>?
    private let onDismiss: (LauncherWindowController) -> Void
    private var results: [ApplicationItem] = []
    private var isRefreshing: Bool
    private var isLaunching = false
    private var launchError: String?
    private var outsideClickMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var displayID: NSNumber?
    private(set) var isPresented = false

    var usesFrostedIcons: Bool {
        didSet {
            guard usesFrostedIcons != oldValue, isPresented else { return }
            rowIcons.removeAllObjects()
            table.reloadData()
            loadResultIcons()
        }
    }

    init(
        index: ApplicationIndex, isRefreshing: Bool, usesFrostedIcons: Bool,
        onDismiss: @escaping (LauncherWindowController) -> Void
    ) {
        self.index = index
        self.isRefreshing = isRefreshing
        self.usesFrostedIcons = usesFrostedIcons
        self.onDismiss = onDismiss
        super.init()
        rowIcons.countLimit = 32
        buildInterface()
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.dismiss() }
        updateResults()
    }

    func present() {
        guard !isPresented else { return }
        isPresented = true
        displayID = nil
        positionPanel(keepTopEdge: false)
        let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        motion.prepareToReveal(in: panel, animated: animated)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        if isPresented {
            observeDismissalEvents()
            loadResultIcons()
            if animated { motion.reveal(in: panel) }
        }
    }

    func dismiss(animated: Bool = true) {
        guard isPresented else {
            if !animated { motion.finish() }
            return
        }
        isPresented = false
        iconTask?.cancel()
        iconTask = nil
        rowIcons.removeAllObjects()

        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        panel.makeFirstResponder(nil)
        if animated, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
           let screen = panel.screen {
            motion.close(from: panel, on: screen) { [weak self] in
                guard let self else { return }
                onDismiss(self)
            }
            panel.close()
        } else {
            panel.close()
            motion.finish()
            onDismiss(self)
        }
    }

    func screenParametersDidChange() {
        motion.finish()
        if isPresented {
            positionPanel(keepTopEdge: false)
            motion.prepareToReveal(in: panel, animated: false)
        }
    }

    func indexWillRefresh() {
        guard isPresented else { return }
        isRefreshing = true
        updatePanelLayout()
    }

    func replaceIndex(_ index: ApplicationIndex) {
        guard isPresented else { return }
        self.index = index
        rowIcons.removeAllObjects()
        isRefreshing = false
        updateResults(reload: true)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard let editor = searchField.currentEditor() as? NSTextView else { return }
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
    }

    func controlTextDidChange(_ notification: Notification) {
        guard isPresented else { return }
        launchError = nil
        updateResults()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)):
            if let event = NSApp.currentEvent, event.type == .keyDown, event.isARepeat { return true }
            launchSelectedApplication()
        default:
            return false
        }
        return true
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = ApplicationRowHighlight.reuseIdentifier
        if let view = tableView.makeView(withIdentifier: identifier, owner: nil) as? ApplicationRowHighlight {
            return view
        }
        let view = ApplicationRowHighlight()
        view.identifier = identifier
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let view = tableView.makeView(withIdentifier: ApplicationRowView.reuseIdentifier, owner: nil) as? ApplicationRowView
            ?? ApplicationRowView(frame: .zero)
        let app = results[row]
        let location = index.duplicateNames.contains(app.name) ? (app.url.path as NSString).abbreviatingWithTildeInPath : nil
        view.configure(with: app, icon: rowIcons.object(forKey: app.url as NSURL) ?? fallbackIcon, location: location)
        view.showsReturnSymbol = row == tableView.selectedRow
        return view
    }

    private func loadResultIcons() {
        iconTask?.cancel()
        iconTask = nil
        guard isPresented else { return }
        let missing = results.filter { rowIcons.object(forKey: $0.url as NSURL) == nil }
        guard !missing.isEmpty else { return }
        let usesFrostedIcons = usesFrostedIcons
        let frostedIconFiles = index.frostedIconFiles
        iconTask = Task(priority: .userInitiated) { [weak self] in
            for app in missing {
                guard !Task.isCancelled else { return }
                let bitmap = await ApplicationIconLoader.shared.icon(
                    for: app, usesFrostedIcons: usesFrostedIcons,
                    frostedIconFile: app.bundleIdentifier.flatMap { frostedIconFiles[$0] }
                )
                guard !Task.isCancelled, let self else { return }
                displayIcon(bitmap, for: app)
            }
        }
    }

    private func displayIcon(_ bitmap: CGImage?, for app: ApplicationItem) {
        let size = ApplicationIconLoader.iconSize
        guard let image = bitmap.map({ NSImage(cgImage: $0, size: NSSize(width: size, height: size)) }) ?? fallbackIcon,
              let row = results.firstIndex(of: app) else { return }
        rowIcons.setObject(image, forKey: app.url as NSURL)
        if let view = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ApplicationRowView {
            view.updateIcon(image)
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        for row in results.indices {
            let view = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ApplicationRowView
            view?.showsReturnSymbol = row == table.selectedRow
        }
    }

    private func buildInterface() {
        panel.contentView = motion.canvas
        motion.updateLayout(in: panel)
        let header = motion.header
        let results = motion.results

        let magnifier = NSImageView()
        magnifier.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 19, weight: .medium))
        magnifier.contentTintColor = .secondaryLabelColor
        magnifier.translatesAutoresizingMaskIntoConstraints = false

        searchField.font = .systemFont(ofSize: 23, weight: .medium)
        searchField.placeholderString = "Search applications…"
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.usesSingleLineMode = true
        searchField.cell?.isScrollable = true
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.setAccessibilityLabel("Search applications")
        searchField.translatesAutoresizingMaskIntoConstraints = false
        panel.initialFirstResponder = searchField

        divider.boxType = .separator
        configureResultsTable()
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageArea.addSubview(messageLabel)

        header.addSubview(magnifier)
        header.addSubview(searchField)
        for view in [divider, scrollView, messageArea] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            results.addSubview(view)
        }

        NSLayoutConstraint.activate([
            magnifier.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 23),
            magnifier.topAnchor.constraint(equalTo: header.topAnchor, constant: 21),
            magnifier.widthAnchor.constraint(equalToConstant: 22),
            magnifier.heightAnchor.constraint(equalToConstant: 22),
            searchField.leadingAnchor.constraint(equalTo: magnifier.trailingAnchor, constant: 13),
            searchField.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -23),
            searchField.centerYAnchor.constraint(equalTo: magnifier.centerYAnchor),
            divider.topAnchor.constraint(equalTo: results.topAnchor),
            divider.leadingAnchor.constraint(equalTo: results.leadingAnchor, constant: 22),
            divider.trailingAnchor.constraint(equalTo: results.trailingAnchor, constant: -22),
            divider.heightAnchor.constraint(equalToConstant: 1),
            listTop,
            listBottom,
            scrollView.leadingAnchor.constraint(equalTo: results.leadingAnchor, constant: 11),
            scrollView.trailingAnchor.constraint(equalTo: results.trailingAnchor, constant: -11),
            messageArea.leadingAnchor.constraint(equalTo: results.leadingAnchor),
            messageArea.trailingAnchor.constraint(equalTo: results.trailingAnchor),
            messageArea.bottomAnchor.constraint(equalTo: results.bottomAnchor),
            messageHeight,
            messageLabel.leadingAnchor.constraint(equalTo: messageArea.leadingAnchor, constant: 23),
            messageLabel.trailingAnchor.constraint(equalTo: messageArea.trailingAnchor, constant: -23),
            messageLabel.centerYAnchor.constraint(equalTo: messageArea.centerYAnchor),
        ])
    }

    private func configureResultsTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Application"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.style = .plain
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.focusRingType = .none
        table.allowsEmptySelection = false
        table.selectionHighlightStyle = .regular
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(launchSelectedApplication)
        table.setAccessibilityLabel("Applications")

        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = table
    }

    private func updateResults(reload: Bool = false) {
        let matches = index.searcher.search(searchField.stringValue, limit: Self.resultLimit)
        if reload || matches != results {
            results = matches
            table.reloadData()
            loadResultIcons()
        }
        if !results.isEmpty {
            selectRow(0)
        }
        updatePanelLayout()
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let selection = table.selectedRow
        let row = selection < 0 ? 0 : min(max(selection + offset, 0), results.count - 1)
        selectRow(row)
    }

    private func selectRow(_ row: Int) {
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func launchSelectedApplication() {
        guard results.indices.contains(table.selectedRow), !isLaunching else { return }
        let application = results[table.selectedRow]
        isLaunching = true
        launchError = nil
        updatePanelLayout()

        Task { [weak self] in
            defer { self?.isLaunching = false }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.allowsRunningApplicationSubstitution = false

            do {
                _ = try await NSWorkspace.shared.openApplication(at: application.url, configuration: configuration)
                self?.dismiss()
            } catch {
                guard let self else { return }
                let failure = error as NSError
                logger.error("Could not open an application (\(failure.domain, privacy: .public) \(failure.code)).")
                guard isPresented else { return }
                launchError = "Couldn’t open \(application.name). Try Refresh Applications."
                updatePanelLayout()
            }
        }
    }

    private func updatePanelLayout() {
        let hasResults = !results.isEmpty
        let inset = hasResults ? Self.listInset : 0
        let statusHeight: CGFloat
        if hasResults {
            statusHeight = launchError == nil ? 0 : Self.errorMessageHeight
            messageLabel.stringValue = launchError ?? ""
        } else {
            statusHeight = Self.emptyMessageHeight
            if index.searcher.isEmpty {
                messageLabel.stringValue = isRefreshing ? "Finding applications…" : "No applications found."
            } else {
                messageLabel.stringValue = "No matching applications."
            }
        }
        messageArea.isHidden = statusHeight == 0
        scrollView.isHidden = !hasResults
        listTop.constant = inset
        listBottom.constant = inset
        messageHeight.constant = statusHeight

        let height = Self.searchHeight + 1 + 2 * inset + Self.rowHeight * CGFloat(results.count) + statusHeight
        if height != contentHeight {
            contentHeight = height
            if isPresented {
                positionPanel(keepTopEdge: true)
            } else {
                panel.setContentSize(NSSize(width: panel.frame.width, height: height))
                motion.updateLayout(in: panel)
            }
        }
    }

    private func positionPanel(keepTopEdge: Bool) {
        let screens = NSScreen.screens
        let pointer = NSEvent.mouseLocation
        guard let screen = screens.first(where: { displayID != nil && $0.flareDisplayID == displayID })
            ?? screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main else { return }

        displayID = screen.flareDisplayID
        let area = screen.visibleFrame
        guard area.width > 32, area.height > Self.searchHeight + 25 else { return }
        let width = min(Self.width, area.width - 32)
        let height = min(contentHeight, area.height - 24)
        let preferredCenter = area.midY + (area.maxY - area.midY) * 0.2
        let y = keepTopEdge ? panel.frame.maxY - height : preferredCenter - height / 2
        let frame = NSRect(
            x: (area.midX - width / 2).rounded(),
            y: min(max(y.rounded(), area.minY + 12), area.maxY - height - 12),
            width: width,
            height: height
        )
        if panel.frame != frame {
            panel.setFrame(frame, display: false)
            motion.updateLayout(in: panel)
        }
    }

    private func observeDismissalEvents() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            // AppKit delivers event monitor callbacks on the main thread.
            MainActor.assumeIsolated { self?.dismiss() }
        }

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss(animated: name != NSWorkspace.activeSpaceDidChangeNotification) }
            }
        }
    }
}

private extension NSScreen {
    var flareDisplayID: NSNumber? { deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber }
}
