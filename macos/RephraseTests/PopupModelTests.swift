import Foundation
import Testing
@testable import Rephrase

/// Serves a canned response for every request.
nonisolated final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }
}

@Suite(.serialized)
struct PopupModelTests {
    let catalog = Catalog(
        models: [.init(id: "m1", label: "Model One", hint: nil, provider: "anthropic")],
        defaultModel: "m1", modes: ["simple", "default", "rewrite"], styles: ["keep"], tones: ["keep"],
        languages: ["auto"], formats: ["markdown", "plain"]
    )

    func makeModel() -> PopupModel {
        PopupModel(original: "i has a idea", options: RephraseOptions(), model: "m1", catalog: catalog) {
            var client = RephraseClient(baseURL: URL(string: "https://stub.test")!, token: "t")
            client.session = StubProtocol.session()
            return client
        }
    }

    func waitUntilSettled(_ model: PopupModel) async {
        for _ in 0..<200 where model.phase == .streaming {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func streamsAndCleansResult() async {
        StubProtocol.status = 200
        StubProtocol.body = """
        data: {"type":"delta","text":"I have "}

        data: {"type":"delta","text":"an idea — really.\\n"}

        data: {"type":"done","model":"m1"}

        """
        let model = makeModel()
        model.onReplace = { _ in }
        model.run()
        await waitUntilSettled(model)
        #expect(model.phase == .done)
        #expect(model.result == "I have an idea - really.")
        #expect(model.canReplace)
        #expect(model.modelLabel == "Model One")
    }

    @Test func showsServerError() async {
        StubProtocol.status = 401
        StubProtocol.body = #"{"error":"Sign in required","code":"unauthorized"}"#
        let model = makeModel()
        model.run()
        await waitUntilSettled(model)
        #expect(model.phase == .failed("Sign in required"))
        #expect(!model.canReplace)
    }

    @Test func showsStreamError() async {
        StubProtocol.status = 200
        StubProtocol.body = "data: {\"type\":\"error\",\"message\":\"Overloaded\",\"status\":529}\n\n"
        let model = makeModel()
        model.run()
        await waitUntilSettled(model)
        #expect(model.phase == .failed("Overloaded"))
    }
}

@Suite(.serialized)
struct QuickReplaceTests {
    @Test func nonStreamingCall() async throws {
        StubProtocol.status = 200
        StubProtocol.body = #"{"text":"I have an idea.","model":"m1","provider":"anthropic","usage":null}"#
        var client = RephraseClient(baseURL: URL(string: "https://stub.test")!, token: "t")
        client.session = StubProtocol.session()
        let result = try await client.rephraseOnce(RephraseRequest(text: "i has a idea", options: RephraseOptions(), model: "m1"))
        #expect(result.text == "I have an idea.")
        #expect(result.model == "m1")
    }

    @Test func nonStreamingError() async {
        StubProtocol.status = 502
        StubProtocol.body = #"{"error":"The model returned no text. Try again or pick another model."}"#
        var client = RephraseClient(baseURL: URL(string: "https://stub.test")!, token: "t")
        client.session = StubProtocol.session()
        await #expect(throws: APIError.message("The model returned no text. Try again or pick another model.")) {
            try await client.rephraseOnce(RephraseRequest(text: "x", options: RephraseOptions(), model: nil))
        }
    }

    @Test func keepsSelectionEdges() {
        #expect(TextReplacer.preservingEdges(of: "i has idea\n", in: "I have an idea.") == "I have an idea.\n")
        #expect(TextReplacer.preservingEdges(of: "  two spaces ", in: "Two spaces.") == "  Two spaces. ")
        #expect(TextReplacer.preservingEdges(of: "no edges", in: " No edges. ") == "No edges.")
        #expect(TextReplacer.preservingEdges(of: "\n\n", in: "x") == "x")
    }
}
