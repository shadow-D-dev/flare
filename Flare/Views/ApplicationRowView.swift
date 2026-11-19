import AppKit

final class ApplicationsTableView: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}

final class ApplicationRowHighlight: NSTableRowView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ApplicationRowHighlight")

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawSelection(in dirtyRect: NSRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Lift the brightness while letting the launcher's blurred backdrop show through.
        NSColor.white.withAlphaComponent(isDark ? 0.14 : 0.34).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 10, yRadius: 10).fill()
    }
}

final class ApplicationRowView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ApplicationRow")

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let locationLabel = NSTextField(labelWithString: "")
    private let returnSymbol = NSImageView()

    var showsReturnSymbol: Bool {
        get { !returnSymbol.isHidden }
        set { returnSymbol.isHidden = !newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseIdentifier
        imageView = iconView
        textField = nameLabel

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .secondaryLabelColor
        nameLabel.font = .systemFont(ofSize: 15, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)

        locationLabel.font = .systemFont(ofSize: 11)
        locationLabel.textColor = .secondaryLabelColor
        locationLabel.lineBreakMode = .byTruncatingMiddle
        locationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        returnSymbol.image = NSImage(systemSymbolName: "return", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        returnSymbol.contentTintColor = .secondaryLabelColor
        returnSymbol.setAccessibilityElement(false)

        for view in [iconView, nameLabel, locationLabel, returnSymbol] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        let iconSize = ApplicationIndexer.iconSize
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 11),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            locationLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 9),
            locationLabel.firstBaselineAnchor.constraint(equalTo: nameLabel.firstBaselineAnchor),
            locationLabel.trailingAnchor.constraint(lessThanOrEqualTo: returnSymbol.leadingAnchor, constant: -12),
            returnSymbol.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            returnSymbol.centerYAnchor.constraint(equalTo: centerYAnchor),
            returnSymbol.widthAnchor.constraint(equalToConstant: 16),
            returnSymbol.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(with application: ApplicationItem, icon: NSImage?, location: String?) {
        nameLabel.stringValue = application.name
        iconView.image = icon
        locationLabel.stringValue = location ?? ""
        locationLabel.toolTip = location
    }
}
