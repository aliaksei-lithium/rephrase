import AppKit
import KeyboardShortcuts

/// Connects the global shortcuts to reading the selection, the popup, quick replace, and pasting.
final class RewriteController {
    private let app: AppModel
    private let popup = PopupController()
    private let badge = BadgeController()
    private var reading = false
    private var quickTask: Task<Void, Never>?
    private var quickRun = 0

    init(app: AppModel) {
        self.app = app
    }

    func registerHotkeys() {
        KeyboardShortcuts.onKeyUp(for: .rewriteWithPopup) { [weak self] in
            Task { await self?.showPopup() }
        }
        KeyboardShortcuts.onKeyUp(for: .rewriteInPlace) { [weak self] in
            Task { await self?.rewriteInPlace() }
        }
    }

    // MARK: ⌃⌥C

    func showPopup() async {
        if popup.isVisible {
            popup.close()
            return
        }
        cancelQuick()
        guard let selection = await readSelection(report: { [popup] message, bounds in
            popup.show(.message(message), near: bounds)
        }) else { return }

        let model = PopupModel(
            original: selection.text,
            options: app.options,
            model: app.effectiveModel,
            catalog: app.catalog,
            makeClient: { [app] in try app.client() }
        )
        model.onClose = { [weak popup] in popup?.close() }
        model.onReplace = { [weak self] text in
            Task { await self?.paste(text, into: selection, closing: { self?.popup.close() }) }
        }
        popup.show(model, near: selection.bounds)
        model.run()
    }

    // MARK: ⌃⌥X

    /// Rewrites with the default settings and pastes over the selection. Pressing the
    /// shortcut again, Esc, or clicking elsewhere while it runs cancels it.
    func rewriteInPlace() async {
        if quickTask != nil {
            cancelQuick()
            return
        }
        popup.close()
        guard let selection = await readSelection(report: { [badge] message, bounds in
            badge.show(.failure(message), near: bounds)
        }) else { return }

        let request = RephraseRequest(text: selection.text, options: app.options, model: app.effectiveModel)
        let client: RephraseClient
        do {
            client = try app.client()
        } catch {
            badge.show(.failure(error.localizedDescription), near: selection.bounds)
            return
        }

        badge.show(.working, near: selection.bounds) { [weak self] in self?.cancelQuick() }
        quickRun += 1
        let run = quickRun
        quickTask = Task { [weak self] in
            defer { if self?.quickRun == run { self?.quickTask = nil } }
            do {
                let result = try await client.rephraseOnce(request)
                try Task.checkCancellation()
                guard let self else { return }
                let text = OutputCleaner.clean(result.text)
                guard !text.isEmpty else {
                    badge.show(.failure("The model returned no text. Try again."), near: selection.bounds)
                    return
                }
                if text == selection.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                    badge.show(.info("Already looks good"), near: selection.bounds)
                    return
                }
                await paste(text, into: selection, closing: { self.badge.close() })
            } catch is CancellationError {
                // Cancelled by the user.
            } catch let error as URLError where error.code == .cancelled {
                // Cancelled by the user.
            } catch {
                self?.badge.show(.failure(error.localizedDescription), near: selection.bounds)
            }
        }
    }

    private func cancelQuick() {
        quickTask?.cancel()
        quickTask = nil
        badge.close()
    }

    // MARK: Shared

    /// Reads the selection and checks sign-in. Problems are shown with `report`; returns nil then.
    private func readSelection(report: (String, CGRect?) -> Void) async -> Selection? {
        guard !reading else { return nil }
        reading = true
        defer { reading = false }

        let selection: Selection
        do {
            selection = try await SelectionReader.read()
        } catch SelectionError.notTrusted {
            SelectionReader.requestTrust()
            return nil
        } catch {
            report(error.localizedDescription, nil)
            return nil
        }
        guard case .signedIn = app.auth else {
            report("Sign in first: open Settings from the Rephrase menu bar icon.", selection.bounds)
            return nil
        }
        return selection
    }

    /// Closes our key panel so the source app gets keyboard focus back, then pastes.
    private func paste(_ text: String, into selection: Selection, closing close: () -> Void) async {
        close()
        try? await Task.sleep(for: .milliseconds(60))
        switch await TextReplacer.replace(selection, with: text) {
        case .replaced:
            badge.show(.success("Replaced · ⌘Z to undo"), near: selection.bounds)
        case .copiedInstead:
            badge.show(.failure("The text field changed, so the result was copied instead. Paste it with ⌘V."), near: selection.bounds)
        }
    }
}
