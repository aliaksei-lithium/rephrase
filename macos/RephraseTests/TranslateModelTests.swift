import Foundation
import Testing
@testable import Rephrase

@Suite(.serialized)
struct TranslateModelTests {
    let languages = [TranslateLanguage(code: "de", name: "German"), TranslateLanguage(code: "en", name: "English")]

    func makeModel(_ text: String = "Hallo Welt", options: TranslateOptions = .init(target: "en")) -> TranslateModel {
        TranslateModel(original: text, options: options, languages: languages) {
            var client = RephraseClient(baseURL: URL(string: "https://stub.test")!, token: "t")
            client.session = StubProtocol.session()
            return client
        }
    }

    func waitUntilSettled(_ model: TranslateModel) async {
        for _ in 0..<200 where model.phase == .loading {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func translatesAndReportsLanguages() async {
        StubProtocol.status = 200
        StubProtocol.body = #"{"text":" Hello world\n","source":"de","target":"en"}"#
        let model = makeModel()
        model.onReplace = { _ in }
        model.run()
        await waitUntilSettled(model)
        #expect(model.phase == .done)
        #expect(model.result == "Hello world")
        #expect(model.name(of: model.source) == "German")
        #expect(model.usedTarget == "en")
        #expect(model.canReplace)
        #expect(!model.isUnchanged)
    }

    @Test func alreadyInTargetIsUnchanged() async {
        StubProtocol.status = 200
        StubProtocol.body = #"{"text":"Hello","source":"en","target":"en"}"#
        let model = makeModel("Hello")
        model.run()
        await waitUntilSettled(model)
        #expect(model.isUnchanged)
        #expect(!model.canReplace)
    }

    @Test func showsServerError() async {
        StubProtocol.status = 503
        StubProtocol.body = #"{"error":"Translation is not configured on the server"}"#
        let model = makeModel()
        var reported: Error?
        model.onError = { reported = $0 }
        model.run()
        await waitUntilSettled(model)
        #expect(model.phase == .failed("Translation is not configured on the server"))
        #expect(reported != nil)
    }

    @Test func retargetDropsAlternate() {
        let model = makeModel(options: .init(target: "en", alternate: "de"))
        StubProtocol.status = 200
        StubProtocol.body = #"{"text":"Bonjour","source":"de","target":"fr"}"#
        model.retarget("fr")
        #expect(model.options == TranslateOptions(target: "fr", alternate: nil))
        model.cancel()
    }

    @Test func optionsRoundTrip() {
        let defaults = UserDefaults(suiteName: "TranslateModelTests")!
        defaults.removePersistentDomain(forName: "TranslateModelTests")
        TranslateOptions(target: "de", alternate: "en").save(to: defaults)
        #expect(TranslateOptions(from: defaults) == TranslateOptions(target: "de", alternate: "en"))
        TranslateOptions(target: "de", alternate: nil).save(to: defaults)
        #expect(TranslateOptions(from: defaults).alternate == nil)
    }

    @Test func catalogDecodesTranslateFlag() throws {
        let json = #"{"models":[],"default":null,"modes":[],"styles":[],"tones":[],"languages":[],"translate":true}"#
        let catalog = try RephraseClient.decoder.decode(Catalog.self, from: Data(json.utf8))
        #expect(catalog.translate == true)
    }
}

@Suite struct TranslateOptionsTests {
    @Test func rememberKeepsDistinctFallback() {
        var options = TranslateOptions(target: "en", alternate: "de")
        options.remember(target: "fr")
        #expect(options == TranslateOptions(target: "fr", alternate: "de"))
        options.remember(target: "de")
        #expect(options == TranslateOptions(target: "de", alternate: nil))
    }

    @Test func retargetReportsPick() {
        let model = TranslateModel(original: "x", options: .init(target: "en"), languages: []) {
            throw APIError.message("offline")
        }
        var picked: String?
        model.onRetarget = { picked = $0 }
        model.retarget("ja")
        #expect(picked == "ja")
        model.cancel()
    }
}

@Suite struct AppleTranslationTests {
    @Test func detectsAndPlans() {
        let german = "Ich habe gestern den Bericht geschickt, aber die Zahlen waren falsch."
        #expect(AppleTranslation.plan(german, options: .init(target: "en")) == .translate(source: "de", target: "en"))
    }

    @Test func alreadyInTargetUsesAlternate() {
        let english = "I sent the report yesterday, but the numbers were wrong."
        #expect(AppleTranslation.plan(english, options: .init(target: "en-US", alternate: "de")) == .translate(source: "en", target: "de"))
        #expect(AppleTranslation.plan(english, options: .init(target: "en")) == .unchanged(source: "en"))
    }

    @Test func comparesLanguages() {
        #expect(AppleTranslation.sameLanguage("en", "en-US"))
        #expect(AppleTranslation.sameLanguage("zh-Hans", "zh-CN"))
        #expect(!AppleTranslation.sameLanguage("zh-Hans", "zh-TW"))
        #expect(!AppleTranslation.sameLanguage("de", "en"))
    }

    @Test func engineIsSaved() {
        let defaults = UserDefaults(suiteName: "AppleTranslationTests")!
        defaults.removePersistentDomain(forName: "AppleTranslationTests")
        TranslateOptions(target: "de", engine: .apple).save(to: defaults)
        #expect(TranslateOptions(from: defaults).engine == .apple)
    }

    @Test func unchangedAppleRunNeedsNoNetwork() {
        let model = TranslateModel(original: "I sent the report yesterday, but the numbers were wrong.", options: .init(target: "en"), engine: .apple, languages: []) {
            throw APIError.message("no network for Apple")
        }
        model.run()
        #expect(model.phase == .done)
        #expect(model.isUnchanged)
        #expect(model.source == "en")
    }
}
