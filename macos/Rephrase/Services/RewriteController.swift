import AppKit
import KeyboardShortcuts

/// Connects the global shortcuts to reading the selection, the popup, and replacing the text.
final class RewriteController {
    private let app: AppModel
    private let popup = PopupController()
    private var busy = false

    init(app: AppModel) {
        self.app = app
    }

    func registerHotkeys() {
        KeyboardShortcuts.onKeyUp(for: .rewriteWithPopup) { [weak self] in
            Task { await self?.showPopup() }
        }
    }

    func showPopup() async {
        guard !busy else { return }
        if popup.isVisible {
            popup.close()
            return
        }
        busy = true
        defer { busy = false }

        let selection: Selection
        do {
            selection = try await SelectionReader.read()
        } catch SelectionError.notTrusted {
            SelectionReader.requestTrust()
            return
        } catch {
            popup.show(.message(error.localizedDescription), near: nil)
            return
        }

        guard case .signedIn = app.auth else {
            popup.show(.message("Sign in first: open Settings from the Rephrase menu bar icon."), near: selection.bounds)
            return
        }

        let model = PopupModel(
            original: selection.text,
            options: app.options,
            model: app.effectiveModel,
            catalog: app.catalog,
            makeClient: { [app] in try app.client() }
        )
        model.onClose = { [weak popup] in popup?.close() }
        model.onReplace = { [weak self] text in
            Task { await self?.replace(selection, with: text) }
        }
        popup.show(model, near: selection.bounds)
        model.run()
    }

    private func replace(_ selection: Selection, with text: String) async {
        popup.close()
        // Let the source app's window take keyboard focus back before pasting.
        try? await Task.sleep(for: .milliseconds(60))
        if await TextReplacer.replace(selection, with: text) == .copiedInstead {
            popup.show(.message("The app changed, so the text was copied instead. Paste it with ⌘V."), near: nil)
        }
    }
}
