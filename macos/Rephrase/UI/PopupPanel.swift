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
    private var model: PopupModel?
    private var anchor: CGRect = .zero
    private var placeAbove = false

    func show(_ model: PopupModel, near bounds: CGRect?) {
        close()
        self.model = model
        anchor = bounds ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        placeAbove = false

        let host = NSHostingController(rootView: PopupView(model: model))
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
        model?.cancel()
        model = nil
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
        let size = panel.frame.size
        let gap: CGFloat = 8
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(anchor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero

        // Prefer below the selection; flip above once it would run off the bottom, and stay there.
        if !placeAbove, anchor.minY - gap - size.height < visible.minY, anchor.maxY + gap + size.height <= visible.maxY {
            placeAbove = true
        }
        var origin = CGPoint(
            x: anchor.minX,
            y: placeAbove ? anchor.maxY + gap : anchor.minY - gap - size.height
        )
        origin.x = min(max(origin.x, visible.minX + gap), visible.maxX - size.width - gap)
        origin.y = min(max(origin.y, visible.minY + gap), visible.maxY - size.height - gap)
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
    }
}
