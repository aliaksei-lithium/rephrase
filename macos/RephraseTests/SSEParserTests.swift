import AppKit
import Testing
@testable import Rephrase

struct SSEParserTests {
    @Test func parsesEvents() {
        #expect(SSEParser.event(from: #"data: {"type":"delta","text":"Hi "}"#) == .delta("Hi "))
        #expect(SSEParser.event(from: #"data: {"type":"info","message":"using Gemma","model":"x"}"#) == .info("using Gemma"))
        #expect(SSEParser.event(from: #"data: {"type":"done","model":"claude-sonnet-5","usage":{"input_tokens":3}}"#) == .done(model: "claude-sonnet-5"))
        #expect(SSEParser.event(from: #"data: {"type":"error","message":"Overloaded","status":529}"#) == .failure("Overloaded"))
    }

    @Test func ignoresOtherLines() {
        #expect(SSEParser.event(from: "") == nil)
        #expect(SSEParser.event(from: ": keep-alive") == nil)
        #expect(SSEParser.event(from: "data: not json") == nil)
    }

    @Test func cleansOutput() {
        #expect(OutputCleaner.clean("  ```\nHello there.\n```  ") == "Hello there.")
        #expect(OutputCleaner.clean("<text>\nHello.\n</text>") == "Hello.")
        #expect(OutputCleaner.clean("Pages 3–5 — done") == "Pages 3-5 - done")
        #expect(OutputCleaner.clean("Line one\n\nLine two") == "Line one\n\nLine two")
    }

    @Test func requestUsesPlainFormat() throws {
        var options = RephraseOptions()
        options.mode = "rewrite"
        let body = RephraseRequest(text: "hi", options: options, model: "claude-sonnet-5")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        #expect(json?["format"] as? String == "plain")
        #expect(json?["mode"] as? String == "rewrite")
        #expect(json?["stream"] as? Bool == true)
    }

    @Test func convertsAXRectToAppKit() {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let rect = SelectionReader.appKitRect(fromAX: CGRect(x: 10, y: 100, width: 50, height: 20))
        #expect(rect == CGRect(x: 10, y: primaryHeight - 120, width: 50, height: 20))
    }
}
