import AppKit
import Observation
@preconcurrency import Translation

/// State of one translate popup: the selection, the target language, and the translation.
@Observable
final class TranslateModel {
    enum Phase: Equatable {
        case loading
        case done
        case failed(String)
    }

    let original: String
    var options: TranslateOptions
    let engine: TranslateEngine
    let languages: [TranslateLanguage]
    /// Drives the view's `.translationTask` for Apple: a new value starts a translation, and macOS
    /// asks to download the languages first when needed.
    private(set) var appleConfiguration: TranslationSession.Configuration?
    private(set) var result = ""
    private(set) var phase: Phase = .loading
    /// Detected language of the selection.
    private(set) var source: String?
    /// The language actually used: `options.alternate` when the text was already in the target.
    private(set) var usedTarget: String?

    /// Set by the controller. Nil means the text can only be copied, and `copyOnlyReason` says why.
    var onReplace: ((String) -> Void)?
    var copyOnlyReason: String?
    var onClose: (() -> Void)?
    var onError: ((Error) -> Void)?
    /// Called with the language picked in the popup, so it becomes the default.
    var onRetarget: ((String) -> Void)?

    private let makeClient: () throws -> RephraseClient
    private var task: Task<Void, Never>?

    init(original: String, options: TranslateOptions, engine: TranslateEngine = .google, languages: [TranslateLanguage], makeClient: @escaping () throws -> RephraseClient) {
        self.original = original
        self.options = options
        self.engine = engine
        self.languages = languages
        self.makeClient = makeClient
    }

    var canReplace: Bool { phase == .done && !result.isEmpty && onReplace != nil }
    /// The text was already in the target language and there is no alternate, so nothing changed.
    var isUnchanged: Bool { phase == .done && result == original.trimmingCharacters(in: .whitespacesAndNewlines) }

    func name(of code: String?) -> String {
        guard let code else { return "?" }
        return languages.first { $0.code.caseInsensitiveCompare(code) == .orderedSame }?.name
            ?? Locale.current.localizedString(forLanguageCode: code)
            ?? code.uppercased()
    }

    func run() {
        task?.cancel()
        result = ""
        source = nil
        usedTarget = nil
        phase = .loading
        if engine == .apple {
            runApple()
            return
        }
        let request = TranslateRequest(text: original, target: options.target, alternate: options.alternate)
        task = Task {
            do {
                let response = try await makeClient().translate(request)
                try Task.checkCancellation()
                source = response.source
                usedTarget = response.target
                result = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                phase = result.isEmpty ? .failed("Google Translate returned no text.") : .done
            } catch is CancellationError {
                // A newer run or the popup closing took over.
            } catch {
                if Task.isCancelled { return }
                phase = .failed(error.localizedDescription)
                onError?(error)
            }
        }
    }

    private func runApple() {
        switch AppleTranslation.plan(original, options: options) {
        case .unknownLanguage:
            phase = .failed("Couldn't tell which language this is.")
        case .unchanged(let detected):
            source = detected
            usedTarget = options.target
            result = original.trimmingCharacters(in: .whitespacesAndNewlines)
            phase = .done
        case .translate(let detected, let target):
            source = detected
            usedTarget = target
            task = Task {
                let status = await AppleTranslation.status(from: detected, to: target)
                guard !Task.isCancelled else { return }
                if status == .unsupported {
                    phase = .failed("Apple can't translate \(name(of: detected)) into \(name(of: target)).")
                    return
                }
                let configuration = TranslationSession.Configuration(
                    source: AppleTranslation.language(detected),
                    target: AppleTranslation.language(target)
                )
                if appleConfiguration == configuration {
                    appleConfiguration?.invalidate()
                } else {
                    appleConfiguration = configuration
                }
            }
        }
    }

    /// Called by the view's `.translationTask` with a session for `appleConfiguration`.
    func translate(with session: TranslationSession) async {
        do {
            let response = try await session.translate(original)
            guard phase == .loading else { return }
            result = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            phase = result.isEmpty ? .failed("Apple Translation returned no text.") : .done
        } catch {
            guard phase == .loading, !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Picking another target in the popup re-runs without the alternate, so the pick is what you get,
    /// and makes it the default for the next ⌃⌥Z.
    func retarget(_ code: String) {
        guard code != usedTarget else { return }
        options = TranslateOptions(target: code, alternate: nil)
        onRetarget?(code)
        run()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func replace() {
        guard canReplace else { return }
        onReplace?(result)
    }

    func copy() {
        guard !result.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        onClose?()
    }

    func close() {
        onClose?()
    }
}
