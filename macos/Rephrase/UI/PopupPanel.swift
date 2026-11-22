import AppKit
import SwiftUI

/// A floating panel that takes keyboard focus without activating Rephrase,
/// so the source app stays frontmost and keeps its selection.
final class PopupPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows one popup at a time next to the selection and keeps it on screen as it grows.
final class PopupController: NSObject, NSWindowDelegate {
    private var panel: PopupPanel?
    /// Cancels the request of the popup on screen.
    private var cancel: (() -> Void)?
    private var anchor: CGRect = .zero
    private var placeAbove = false

    func show(_ model: PopupModel, near bounds: CGRect?) {
        show(PopupView(model: model), near: bounds, cancel: model.cancel)
    }

    func show(_ model: TranslateModel, near bounds: CGRect?) {
        show(TranslateView(model: model), near: bounds, cancel: model.cancel)
    }

    private func show(_ view: some View, near bounds: CGRect?, cancel: @escaping () -> Void) {
        close()
        self.cancel = cancel
        anchor = bounds ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        placeAbove = false

        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        let panel = PopupPanel()
        panel.contentViewController = host
        panel.delegate = self
        self.panel = panel

        panel.setContentSize(host.view.fittingSize)
        reposition()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        cancel?()
        cancel = nil
        panel.delegate = nil
        panel.orderOut(nil)
        panel.close()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        reposition()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking elsewhere dismisses the popup.
        close()
    }

    // MARK: Layout

    private func reposition() {
        guard let panel else { return }
        let origin = PanelPlacement.origin(for: panel.frame.size, near: anchor, placeAbove: &placeAbove)
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
    }
}

enum PanelPlacement {
    /// Below the anchor, or above it once that would run off the bottom (and then stays above),
    /// clamped to the visible frame of the anchor's screen.
    static func origin(for size: CGSize, near anchor: CGRect, placeAbove: inout Bool, gap: CGFloat = 8) -> CGPoint {
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(anchor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero

        if !placeAbove, anchor.minY - gap - size.height < visible.minY, anchor.maxY + gap + size.height <= visible.maxY {
            placeAbove = true
        }
        var origin = CGPoint(
            x: anchor.minX,
            y: placeAbove ? anchor.maxY + gap : anchor.minY - gap - size.height
        )
        origin.x = min(max(origin.x, visible.minX + gap), visible.maxX - size.width - gap)
        origin.y = min(max(origin.y, visible.minY + gap), visible.maxY - size.height - gap)
        return origin
    }
}
