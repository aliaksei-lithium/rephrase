import Foundation
import Testing
@testable import Rephrase

/// Runs against a live server only when asked:
/// TEST_RUNNER_REPHRASE_BASE_URL=http://localhost:8788 TEST_RUNNER_APP_PASSWORD=... xcodebuild test ...
struct IntegrationTests {
    nonisolated static let env = ProcessInfo.processInfo.environment

    @Test(.enabled(if: env["REPHRASE_BASE_URL"] != nil && env["APP_PASSWORD"] != nil))
    func signInAndLoadCatalog() async throws {
        let base = try #require(URL(string: Self.env["REPHRASE_BASE_URL"]!))

        await #expect(throws: APIError.unauthorized("Wrong password")) {
            try await RephraseClient(baseURL: base, token: nil).login(password: "definitely-wrong")
        }

        let login = try await RephraseClient(baseURL: base, token: nil).login(password: Self.env["APP_PASSWORD"]!)
        let client = RephraseClient(baseURL: base, token: login.token)
        #expect(try await client.me().authenticated)

        let catalog = try await client.catalog()
        #expect(!catalog.models.isEmpty)
        #expect(catalog.formats?.contains("plain") == true)
    }

    /// Needs a server with the demo (Workers AI binding and DEMO_DB), for example `npm run dev:free`.
    @Test(.enabled(if: env["REPHRASE_BASE_URL"] != nil))
    func demoSessionOffersOnlyGemma() async throws {
        let base = try #require(URL(string: Self.env["REPHRASE_BASE_URL"]!))
        guard try await RephraseClient(baseURL: base, token: nil).me().demoAvailable == true else { return }

        let demo = try await RephraseClient(baseURL: base, token: nil).startDemo()
        let client = RephraseClient(baseURL: base, token: demo.token)
        #expect(try await client.me().demo == true)
        let catalog = try await client.catalog()
        #expect(catalog.demo == true)
        #expect(catalog.models.map(\.id) == ["@cf/google/gemma-4-26b-a4b-it"])
    }

    /// Set TEST_RUNNER_REPHRASE_MODEL to pick a model (for example the free Workers AI one locally).
    @Test(.enabled(if: env["REPHRASE_BASE_URL"] != nil && env["APP_PASSWORD"] != nil))
    func streamsPlainRewrite() async throws {
        let base = try #require(URL(string: Self.env["REPHRASE_BASE_URL"]!))
        let login = try await RephraseClient(baseURL: base, token: nil).login(password: Self.env["APP_PASSWORD"]!)
        let client = RephraseClient(baseURL: base, token: login.token)

        var options = RephraseOptions()
        options.mode = "simple"
        let request = RephraseRequest(text: "i has send the file_v2.txt yesterday", options: options, model: Self.env["REPHRASE_MODEL"])
        var text = ""
        var finished = false
        for try await event in client.rephrase(request) {
            if case .delta(let chunk) = event { text += chunk }
            if case .done = event { finished = true }
        }
        #expect(finished)
        #expect(OutputCleaner.clean(text).contains("file_v2.txt"))
    }
}

struct KeychainStoreTests {
    @Test func roundTrip() throws {
        let store = KeychainStore(service: "dev.rephrase.mac.tests.\(UUID().uuidString)")
        defer { store.deleteToken(for: "example.test") }

        #expect(store.token(for: "example.test") == nil)
        try store.setToken("first", for: "example.test")
        try store.setToken("second", for: "example.test")
        #expect(store.token(for: "example.test") == "second")
        store.deleteToken(for: "example.test")
        #expect(store.token(for: "example.test") == nil)
    }
}
