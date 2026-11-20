import AppKit
import QuartzCore

@MainActor
final class LauncherMotion: NSObject {
    private struct Shape {
        let frame: NSRect
        let radius: CGFloat
        var header: CGFloat
        let results: CGFloat
        var opacity: CGFloat = 1

        func interpolated(to end: Self, progress: CGFloat) -> Self {
            func blend(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * progress }

            return Self(
                frame: NSRect(
                    x: blend(frame.minX, end.frame.minX), y: blend(frame.minY, end.frame.minY),
                    width: blend(frame.width, end.frame.width), height: blend(frame.height, end.frame.height)
                ),
                radius: blend(radius, end.radius), header: blend(header, end.header),
                results: blend(results, end.results), opacity: blend(opacity, end.opacity)
            )
        }
    }

    private static let cornerRadius: CGFloat = 22
    private static let revealDuration: CFTimeInterval = 0.32
    private static let searchBarProgress: CGFloat = 0.54
    private static let closeFadeStart: CGFloat = 0.4

    let canvas = NSView()
    let header = NSView()
    let results = NSView()

    private let surface = LauncherSurface(frame: .zero)
    private let controls = NSView()
    private let headerHeight: CGFloat
    private var displayLink: CADisplayLink?
    private var drawFrame: ((CFTimeInterval) -> Bool)?
    private var closingPanel: LauncherPanel?
    private var closingCompletion: (() -> Void)?
    private var dropletOrigin = NSPoint.zero
    private var revealProgress: CGFloat = 1
    private var renderedPanelFrame: NSRect?

    init(headerHeight: CGFloat) {
        self.headerHeight = headerHeight
        super.init()

        canvas.addSubview(surface)
        surface.contentHost.addSubview(controls)
        controls.addSubview(header)
        controls.addSubview(results)
    }

    func prepareToReveal(in panel: NSWindow, animated: Bool) {
        let frame = panel.frame
        dropletOrigin = NSPoint(x: frame.midX, y: frame.midY)
        revealProgress = animated ? 0 : 1
        render(revealShape(at: revealProgress, in: frame), restingFrame: frame, in: panel)
    }

    func reveal(in panel: NSWindow) {
        guard let screen = panel.screen else {
            prepareToReveal(in: panel, animated: false)
            return
        }
        animate(on: screen) { [weak self, weak panel] elapsed in
            guard let self, let panel else { return false }
            let frame = panel.frame
            revealProgress = min(1, CGFloat(elapsed / Self.revealDuration))
            render(revealShape(at: revealProgress, in: frame), restingFrame: frame, in: panel)
            return revealProgress < 1
        }
    }

    func updateLayout(in panel: NSWindow) {
        // Each reveal frame uses the live panel frame, including when the query changes its size.
        guard displayLink == nil, closingPanel == nil else { return }
        render(restingShape(in: panel.frame), restingFrame: panel.frame, in: panel)
    }

    func close(from panel: LauncherPanel, on screen: NSScreen, completion: @escaping () -> Void) {
        stopDisplayLink()
        let restingFrame = renderedPanelFrame ?? panel.frame
        let startProgress = revealProgress
        let retreat = max(0, startProgress - Self.searchBarProgress * 0.4)
        let returnDuration = max(0.08, Self.revealDuration * Double(retreat))
        let start = revealShape(at: startProgress, in: restingFrame)
        let end = revealShape(at: startProgress - retreat, in: restingFrame)

        // Keep the moving glass in a click-through window so the underlying app gets focus immediately.
        let exitFrame = restingFrame.union(start.frame).union(end.frame)
        let exit = LauncherPanel(size: exitFrame.size, acceptsKeyboard: false)
        let exitCanvas = NSView(frame: NSRect(origin: .zero, size: exitFrame.size))
        exit.contentView = exitCanvas
        exit.setFrame(exitFrame, display: false)
        closingPanel = exit
        closingCompletion = completion
        surface.removeFromSuperview()
        exitCanvas.addSubview(surface)
        render(start, restingFrame: restingFrame, in: exit)
        exit.orderFrontRegardless()

        animate(on: screen) { [weak self, weak exit] elapsed in
            guard let self, let exit else { return false }
            let fraction = CGFloat(elapsed / returnDuration)
            guard fraction < 1 else {
                finish()
                return false
            }

            let fade = max(0, (fraction - Self.closeFadeStart) / (1 - Self.closeFadeStart))
            exit.alphaValue = 1 - Self.smoothStep(fade)
            let progress = startProgress - retreat * fraction
            var shape = revealShape(at: progress, in: restingFrame)
            shape.opacity = start.opacity
            render(shape, restingFrame: restingFrame, in: exit)
            return true
        }
    }

    func finish() {
        stopDisplayLink()
        if let closingPanel {
            surface.removeFromSuperview()
            closingPanel.close()
            self.closingPanel = nil
        }
        renderedPanelFrame = nil
        let completion = closingCompletion
        closingCompletion = nil
        completion?()
    }

    private func render(_ shape: Shape, restingFrame: NSRect, in window: NSWindow) {
        renderedPanelFrame = restingFrame
        let windowOrigin = window.frame.origin

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.frame = shape.frame.offsetBy(dx: -windowOrigin.x, dy: -windowOrigin.y)
        surface.cornerRadius = shape.radius
        surface.alphaValue = shape.opacity
        surface.rimOpacity = Self.smoothStep(Self.clamp((shape.results - 0.65) / 0.35))
        // Hold the controls at their final size while the glass exposes more of their layout.
        controls.frame = restingFrame.offsetBy(dx: -shape.frame.minX, dy: -shape.frame.minY)
        header.frame = NSRect(x: 0, y: restingFrame.height - headerHeight, width: restingFrame.width, height: headerHeight)
        results.frame = NSRect(x: 0, y: 0, width: restingFrame.width, height: max(0, restingFrame.height - headerHeight))
        header.alphaValue = shape.header
        results.alphaValue = shape.results
        CATransaction.commit()
    }

    private func restingShape(in frame: NSRect) -> Shape {
        Shape(frame: frame, radius: Self.cornerRadius, header: 1, results: 1)
    }

    private func revealShape(at progress: CGFloat, in frame: NSRect) -> Shape {
        let resting = restingShape(in: frame)
        guard progress < 1 else { return resting }

        let bar = Shape(
            frame: NSRect(x: frame.minX, y: frame.maxY - headerHeight, width: frame.width, height: headerHeight),
            radius: headerHeight / 2, header: 1, results: 0
        )
        if progress >= Self.searchBarProgress {
            let part = (progress - Self.searchBarProgress) / (1 - Self.searchBarProgress)
            return bar.interpolated(to: resting, progress: Self.smoothStep(part))
        }

        let part = progress / Self.searchBarProgress
        var shape = droplet(at: dropletOrigin).interpolated(to: bar, progress: Self.smoothStep(part))
        shape.header = Self.clamp((part - 0.48) / 0.52)
        return shape
    }

    private func droplet(at center: NSPoint) -> Shape {
        Shape(frame: NSRect(x: center.x - 9, y: center.y - 10, width: 18, height: 20),
              radius: 9, header: 0, results: 0, opacity: 0)
    }

    private func animate(on screen: NSScreen, draw: @escaping (CFTimeInterval) -> Bool) {
        // Start the clock at the first refresh so even a cold reveal shows the droplet.
        var firstFrame: CFTimeInterval?
        drawFrame = { timestamp in
            if firstFrame == nil { firstFrame = timestamp }
            return draw(timestamp - (firstFrame ?? timestamp))
        }
        let link = screen.displayLink(target: self, selector: #selector(displayFrame(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func displayFrame(_ link: CADisplayLink) {
        if drawFrame?(link.targetTimestamp) != true {
            stopDisplayLink()
        }
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        drawFrame = nil
    }

    private static func smoothStep(_ progress: CGFloat) -> CGFloat {
        progress * progress * (3 - 2 * progress)
    }

    private static func clamp(_ value: CGFloat) -> CGFloat { min(max(0, value), 1) }
}
