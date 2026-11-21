import Foundation

/// One event from the /api/rephrase stream.
enum RephraseEvent: Equatable {
    case delta(String)
    case info(String)
    case done(model: String?)
    case failure(String)
}

/// Parses the `data: {...}` lines of the server-sent event stream. Other lines are ignored.
enum SSEParser {
    private struct Raw: Decodable {
        let type: String
        let text: String?
        let message: String?
        let model: String?
    }

    static func event(from line: Substring) -> RephraseEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let raw = try? JSONDecoder().decode(Raw.self, from: Data(payload.utf8)) else { return nil }
        switch raw.type {
        case "delta": return raw.text.map(RephraseEvent.delta)
        case "info": return .info(raw.message ?? "")
        case "done": return .done(model: raw.model)
        case "error": return .failure(raw.message ?? "Unexpected error")
        default: return nil
        }
    }

    static func event(from line: String) -> RephraseEvent? {
        event(from: line[...])
    }
}

/// Strips wrappers a model sometimes adds and replaces long dashes, like the web client does.
enum OutputCleaner {
    static func clean(_ raw: String) -> String {
        var out = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = out.wholeMatch(of: /```[a-zA-Z]*\n([\s\S]*?)\n```/) {
            out = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        out = out.replacing(/^<text>\s*/.ignoresCase(), with: "")
            .replacing(/\s*<\/text>$/.ignoresCase(), with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        out = out.replacing(/(\d)\s*[–—]\s*(\d)/) { "\($0.1)-\($0.2)" }
        return out.replacing(/[ \t]*[–—][ \t]*/, with: " - ")
    }
}
