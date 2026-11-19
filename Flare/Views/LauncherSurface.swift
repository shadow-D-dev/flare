import AppKit

final class LauncherSurface: NSView {
    let contentHost = NSView()
    private let backdrop = NSVisualEffectView()
    private var rimAlpha: CGFloat = 0

    var cornerRadius: CGFloat = 22 {
        didSet {
            backdrop.layer?.cornerRadius = cornerRadius
        }
    }

    var rimOpacity: CGFloat = 1 {
        didSet {
            if oldValue != rimOpacity { updateRim() }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        backdrop.frame = bounds
        backdrop.autoresizingMask = [.width, .height]
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = cornerRadius
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds = true
        backdrop.layer?.borderWidth = 0.75

        contentHost.frame = backdrop.bounds
        contentHost.autoresizingMask = [.width, .height]
        contentHost.wantsLayer = true
        backdrop.addSubview(contentHost)
        addSubview(backdrop)
        updateFinish()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFinish()
    }

    private func updateFinish() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        backdrop.material = isDark ? .hudWindow : .popover
        let tint = isDark
            ? NSColor(srgbRed: 0.052, green: 0.071, blue: 0.116, alpha: 0.42)
            : NSColor(srgbRed: 0.89, green: 0.92, blue: 0.97, alpha: 0.24)
        contentHost.layer?.backgroundColor = tint.cgColor
        rimAlpha = isDark ? 0.16 : 0.56
        updateRim()
    }

    private func updateRim() {
        backdrop.layer?.borderColor = NSColor.white.withAlphaComponent(rimAlpha * rimOpacity).cgColor
    }
}
