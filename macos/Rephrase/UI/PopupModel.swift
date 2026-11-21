import AppKit
import Observation

/// State of one popup: the original selection, the options used, and the streamed result.
@Observable
final class PopupModel {
    enum Phase: Equatable {
        case streaming
        case done
        case failed(String)
    }

    let original: String
    var options: RephraseOptions
    let catalog: Catalog?
    private(set) var result = ""
    private(set) var phase: Phase = .streaming
    private(set) var note: String?
    private(set) var modelLabel: String?

    /// Called by the controller; nil when there is no selection to write back to.
    var onReplace: ((String) -> Void)?
    var onClose: (() -> Void)?

    private let makeClient: () throws -> RephraseClient
    private let model: String?
    private var task: Task<Void, Never>?

    init(original: String, options: RephraseOptions, model: String?, catalog: Catalog?, makeClient: @escaping () throws -> RephraseClient) {
        self.original = original
        self.options = options
        self.model = model
        self.catalog = catalog
        self.makeClient = makeClient
        modelLabel = catalog?.models.first { $0.id == model }?.title
    }

    /// A popup that only shows a message (nothing selected, not signed in, ...).
    static func message(_ text: String) -> PopupModel {
        let model = PopupModel(original: "", options: RephraseOptions(), model: nil, catalog: nil) {
            throw APIError.message(text)
        }
        model.phase = .failed(text)
        return model
    }

    var canReplace: Bool { phase == .done && !result.isEmpty && onReplace != nil }
    var isUnchanged: Bool { phase == .done && result == original.trimmingCharacters(in: .whitespacesAndNewlines) }

    func run() {
        task?.cancel()
        result = ""
        note = nil
        phase = .streaming
        let request = RephraseRequest(text: original, options: options, model: model)
        task = Task {
            var streamed = ""
            do {
                for try await event in try makeClient().rephrase(request) {
                    switch event {
                    case .delta(let text):
                        streamed += text
                        result = streamed
                    case .info(let message):
                        note = message
                    case .done(let usedModel):
                        if let usedModel { modelLabel = catalog?.models.first { $0.id == usedModel }?.title ?? usedModel }
                    case .failure(let message):
                        throw APIError.message(message)
                    }
                }
                try Task.checkCancellation()
                result = OutputCleaner.clean(streamed)
                phase = result.isEmpty ? .failed("The model returned no text. Try again.") : .done
            } catch is CancellationError {
                // A newer run or the popup closing took over.
            } catch {
                if Task.isCancelled { return }
                phase = .failed(error.localizedDescription)
            }
        }
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
