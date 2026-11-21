import Foundation
import Testing
@testable import Rephrase

struct RephraseClientTests {
    @Test func decodesCatalog() throws {
        let json = """
        {"models":[{"id":"claude-sonnet-5","label":"Claude Sonnet 5","hint":"fast","provider":"anthropic","price":{"input":2,"output":10}}],
         "default":"claude-sonnet-5","modes":["simple","default","rewrite"],"styles":["keep"],"tones":["keep"],
         "languages":["auto","en","de"],"formats":["markdown","plain"]}
        """
        let catalog = try RephraseClient.decoder.decode(Catalog.self, from: Data(json.utf8))
        #expect(catalog.defaultModel == "claude-sonnet-5")
        #expect(catalog.models.first?.title == "Claude Sonnet 5")
        #expect(catalog.formats == ["markdown", "plain"])
    }

    @Test func decodesLoginDate() throws {
        let json = #"{"ok":true,"token":"abc.def","expires_at":"2027-05-20T10:00:00.000Z"}"#
        let login = try RephraseClient.decoder.decode(LoginResponse.self, from: Data(json.utf8))
        #expect(login.token == "abc.def")
        #expect(login.expiresAt == Date(timeIntervalSince1970: 1_810_807_200))
    }

    @Test func decodesDemoSession() throws {
        let me = try RephraseClient.decoder.decode(MeResponse.self, from: Data(#"{"authenticated":true,"configured":true,"demo":true,"demo_available":true,"expires_at":"2027-05-20T10:00:00.000Z"}"#.utf8))
        #expect(me.demo == true)
        #expect(me.demoAvailable == true)

        // Servers without the demo send neither field.
        let old = try RephraseClient.decoder.decode(MeResponse.self, from: Data(#"{"authenticated":false,"expires_at":null}"#.utf8))
        #expect(old.demo == nil)
        #expect(old.demoAvailable == nil)
    }

    @Test func mapsDemoLimit() {
        let body = Data(#"{"error":"The free demo has used up today's quota.","code":"demo_limit"}"#.utf8)
        #expect(APIError.from(status: 429, data: body) == .message("The free demo has used up today's quota."))
    }

    @Test func mapsServerErrors() {
        let body = Data(#"{"error":"Wrong password","code":"bad_password"}"#.utf8)
        #expect(APIError.from(status: 401, data: body) == .unauthorized("Wrong password"))
        #expect(APIError.from(status: 500, data: Data()).errorDescription == "Internal Server Error")
    }
}
