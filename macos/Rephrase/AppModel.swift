import Foundation
import Observation

/// App-wide state: server, sign-in, the catalog from /api/models, and the default rewrite settings.
@Observable
final class AppModel {
    enum AuthState: Equatable {
        case unknown
        case signedOut
        case signedIn(expiresAt: Date?)
    }

    static let defaultServer = "https://rephrase-eey.pages.dev"

    private(set) var auth: AuthState = .unknown
    private(set) var catalog: Catalog?
    private(set) var lastError: String?
    private(set) var isBusy = false

    var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Keys.server) }
    }

    var options: RephraseOptions {
        didSet { options.save(to: defaults) }
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        serverURL = defaults.string(forKey: Keys.server) ?? Self.defaultServer
        options = RephraseOptions(from: defaults)
        Task { await refresh() }
    }

    var statusText: String {
        switch auth {
        case .unknown: "Connecting…"
        case .signedOut: "Not signed in"
        case .signedIn: "Signed in to \(host)"
        }
    }

    var host: String {
        URL(string: serverURL)?.host() ?? serverURL
    }

    /// The model to send: the saved choice if the server still offers it, else the server default.
    var effectiveModel: String? {
        guard let catalog else { return options.model }
        if let saved = options.model, catalog.models.contains(where: { $0.id == saved }) { return saved }
        return catalog.defaultModel ?? catalog.models.first?.id
    }

    func client() throws -> RephraseClient {
        guard let url = URL(string: serverURL), url.scheme == "https" || url.scheme == "http" else {
            throw APIError.message("Server URL is not valid")
        }
        return RephraseClient(baseURL: url, token: keychain.token(for: host))
    }

    func signIn(password: String) async {
        await run {
            let response = try await client().login(password: password)
            try keychain.setToken(response.token, for: host)
            auth = .signedIn(expiresAt: response.expiresAt)
            catalog = try await client().catalog()
        }
    }

    func signOut() {
        keychain.deleteToken(for: host)
        auth = .signedOut
        catalog = nil
    }

    /// A 401 from any request means the token expired or the server secret changed.
    func handleRequestError(_ error: Error) {
        guard case APIError.unauthorized = error else { return }
        keychain.deleteToken(for: host)
        auth = .signedOut
        catalog = nil
        lastError = "Your session expired. Sign in again."
    }

    /// Checks the stored token and reloads the catalog. Called at launch and after the server changes.
    func refresh() async {
        await run {
            let client = try client()
            guard client.token != nil else {
                auth = .signedOut
                catalog = nil
                return
            }
            let me = try await client.me()
            if me.authenticated {
                auth = .signedIn(expiresAt: me.expiresAt)
                catalog = try await client.catalog()
            } else {
                keychain.deleteToken(for: host)
                auth = .signedOut
                catalog = nil
            }
        }
    }

    private func run(_ work: () async throws -> Void) async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            lastError = error.localizedDescription
            if auth == .unknown { auth = .signedOut }
        }
    }

    private enum Keys {
        static let server = "serverURL"
    }
}

/// Default settings for both shortcuts. Values are the API's ids.
struct RephraseOptions: Equatable {
    var mode = "default"
    var style = "keep"
    var tone = "keep"
    var language = "auto"
    var model: String?

    init() {}

    init(from defaults: UserDefaults) {
        mode = defaults.string(forKey: "mode") ?? mode
        style = defaults.string(forKey: "style") ?? style
        tone = defaults.string(forKey: "tone") ?? tone
        language = defaults.string(forKey: "language") ?? language
        model = defaults.string(forKey: "model")
    }

    func save(to defaults: UserDefaults) {
        defaults.set(mode, forKey: "mode")
        defaults.set(style, forKey: "style")
        defaults.set(tone, forKey: "tone")
        defaults.set(language, forKey: "language")
        defaults.set(model, forKey: "model")
    }
}
