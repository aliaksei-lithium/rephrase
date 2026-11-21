import AppKit
import SwiftUI

/// The small status badge for quick replace.
enum BadgeState: Equatable {
    case working
    case success(String)
    case info(String)
    case failure(String)
}

private struct BadgeView: View {
    let state: BadgeState
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .working:
                ProgressView().controlSize(.small)
                Text("Rewriting…")
                Button("Cancel", systemImage: "xmark", action: onCancel)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .help("Cancel (Esc)")
            case .success(let text):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(text)
            case .info(let text):
                Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
                Text(text)
            case .failure(let text):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(text)
                    .lineLimit(3)
                    .frame(maxWidth: 300, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .padding(1)
        .fixedSize()
    }
}

/// Shows one badge at a time. While working it takes keyboard focus (without activating
/// Rephrase) so Esc can cancel; result badges never take focus and hide on their own.
final class BadgeController: NSObject, NSWindowDelegate {
    private var panel: PopupPanel?
    private var anchor: CGRect = .zero
    private var generation = 0
    private var onCancel: (() -> Void)?

    func show(_ state: BadgeState, near bounds: CGRect?, onCancel: (() -> Void)? = nil) {
        close()
        generation += 1
        let current = generation
        if let bounds { anchor = bounds } else if state == .working || anchor == .zero {
            anchor = CGRect(origin: NSEvent.mouseLocation, size: .zero)
        }
        self.onCancel = onCancel

        let host = NSHostingView(rootView: BadgeView(state: state) { [weak self] in self?.cancel() })
        let panel = PopupPanel()
        panel.isMovableByWindowBackground = false
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        var placeAbove = false
        panel.setFrameOrigin(PanelPlacement.origin(for: panel.frame.size, near: anchor, placeAbove: &placeAbove))
        self.panel = panel

        panel.orderFrontRegardless()
        if state == .working {
            panel.delegate = self
            panel.makeKey()
        } else {
            panel.ignoresMouseEvents = true
            let delay: Duration = if case .failure = state { .seconds(3) } else { .seconds(1.2) }
            Task { [weak self] in
                try? await Task.sleep(for: delay)
                if self?.generation == current { self?.close() }
            }
        }
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        onCancel = nil
        panel.delegate = nil
        panel.orderOut(nil)
        panel.close()
    }

    private func cancel() {
        let handler = onCancel
        close()
        handler?()
    }

    // Clicking elsewhere while working cancels: the paste target would no longer be certain.
    func windowDidResignKey(_ notification: Notification) {
        cancel()
    }
}
