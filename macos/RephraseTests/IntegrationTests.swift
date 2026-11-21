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
