import Foundation
import Testing
@testable import Rephrase

struct DiffTextTests {
    @Test func tokensRoundTrip() {
        let text = "Hi  team,\nthe numbers\twas wrong. "
        #expect(DiffText.tokens(text).joined() == text)
    }

    @Test func marksChangedWordsOnly() {
        let original = "the numbers was wrong"
        let result = "The numbers were wrong."
        let tokens = DiffText.tokens(result)
        let marked = DiffText.insertedIndices(original: original, result: result).sorted().map { String(tokens[$0]) }
        #expect(marked == ["The", "were", "wrong."])
    }

    @Test func unchangedTextHasNoMarks() {
        #expect(DiffText.insertedIndices(original: "All good here.", result: "All good here.").isEmpty)
    }

    @Test func whitespaceChangesAreNotMarked() {
        #expect(DiffText.insertedIndices(original: "a  b", result: "a b").isEmpty)
    }

    @Test func attributedKeepsText() {
        let attributed = DiffText.attributed(original: "i has idea", result: "I have an idea.")
        #expect(String(attributed.characters) == "I have an idea.")
    }

    @Test func terminalsAreCopyOnly() {
        #expect(TerminalApps.contains("com.apple.Terminal"))
        #expect(TerminalApps.contains("com.googlecode.iterm2"))
        #expect(!TerminalApps.contains("com.apple.TextEdit"))
        #expect(!TerminalApps.contains(nil))
    }
}
