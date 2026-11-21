import SwiftUI

/// Marks the words the rewrite added or changed, like the web app's underlines.
enum DiffText {
    /// Splits into alternating runs of whitespace and non-whitespace, so joining the tokens gives the text back.
    static func tokens(_ text: String) -> [Substring] {
        text.matches(of: /\s+|\S+/).map { text[$0.range] }
    }

    /// Indices of tokens in `result` that are not in `original` (by word, ignoring whitespace changes).
    static func insertedIndices(original: String, result: String) -> Set<Int> {
        let old = tokens(original)
        let new = tokens(result)
        var inserted = Set<Int>()
        for change in new.difference(from: old) {
            if case .insert(let offset, let token, _) = change, !token.allSatisfy(\.isWhitespace) {
                inserted.insert(offset)
            }
        }
        return inserted
    }

    static func attributed(original: String, result: String) -> AttributedString {
        let inserted = insertedIndices(original: original, result: result)
        var output = AttributedString()
        for (index, token) in tokens(result).enumerated() {
            var piece = AttributedString(token)
            if inserted.contains(index) {
                piece.underlineStyle = Text.LineStyle(pattern: .solid, color: .accentColor)
                piece.backgroundColor = Color.accentColor.opacity(0.12)
            }
            output += piece
        }
        return output
    }
}
