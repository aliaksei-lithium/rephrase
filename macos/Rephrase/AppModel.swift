import Foundation
import Observation

/// App-wide state: server, sign-in, the catalog from /api/models, and the default rewrite settings.
@Observable
final class AppModel {
    enum AuthState: Equatable {
        case unknown
        case signedOut
        /// demo: a public demo session (free Gemma model only, shared daily limit).
        case signedIn(expiresAt: Date?, demo: Bool = false)
    }

    static let defaultServer = "https://rephrase.aliaksei.xyz"
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    /// Earlier defaults. A saved value equal to one of these follows the current default.
    static let legacyServers = ["https://rephrase-eey.pages.dev"]

    private(set) var auth: AuthState = .unknown
    private(set) var catalog: Catalog?
    private(set) var lastError: String?
    private(set) var isBusy = false
    /// The server offers the public demo. Unknown (nil) until /api/auth/me answered.
    private(set) var demoAvailable: Bool?

    var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Keys.server) }
    }

    var options: RephraseOptions {
        didSet { options.save(to: defaults) }
    }

    var translateOptions: TranslateOptions {
        didSet { translateOptions.save(to: defaults) }
    }

    /// Languages for the translate pickers, loaded from /api/translate once the server says it can translate.
    private(set) var translateLanguages: [TranslateLanguage] = []

    /// Languages Apple's on-device translation supports.
    private(set) var appleLanguages: [TranslateLanguage] = []

    /// Signed in with the password and the server has a Google Translate key, so Google can be used.
    var canTranslate: Bool {
        if case .signedIn(_, demo: false) = auth { catalog?.translate == true } else { false }
    }

    /// Google when it is available and chosen; otherwise Apple, which works signed out and in the demo.
    var translateEngine: TranslateEngine {
        canTranslate && translateOptions.engine == .google ? .google : .apple
    }

    func translateLanguages(for engine: TranslateEngine) -> [TranslateLanguage] {
        let list = engine == .google ? translateLanguages : appleLanguages
        return list.isEmpty ? TranslateLanguage.common : list
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        serverURL = defaults.string(forKey: Keys.server) ?? Self.defaultServer
        options = RephraseOptions(from: defaults)
        translateOptions = TranslateOptions(from: defaults)
        migrateLegacyServer()
        // Unit tests run inside the app: don't read the real keychain (macOS would block on an
        // access prompt for the Debug build) or call the server.
        guard !Self.isRunningTests else { return }
        Task {
            await refresh()
            await loadTranslateLanguages()
        }
    }

    var statusText: String {
        switch auth {
        case .unknown: "Connecting…"
        case .signedOut: "Not signed in"
        case .signedIn(_, demo: true): "Demo on \(host) (Gemma only)"
        case .signedIn: "Signed in to \(host)"
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = auth { true } else { false }
    }

    var isDemo: Bool {
        if case .signedIn(_, demo: true) = auth { true } else { false }
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
            await loadTranslateLanguages()
        }
    }

    func startDemo() async {
        await run {
            let response = try await client().startDemo()
            try keychain.setToken(response.token, for: host)
            auth = .signedIn(expiresAt: response.expiresAt, demo: true)
            demoAvailable = true
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
            let me = try await client.me()
            demoAvailable = me.demoAvailable ?? false
            guard client.token != nil else {
                auth = .signedOut
                catalog = nil
                return
            }
            if me.authenticated {
                auth = .signedIn(expiresAt: me.expiresAt, demo: me.demo ?? false)
                catalog = try await client.catalog()
                await loadTranslateLanguages()
            } else {
                keychain.deleteToken(for: host)
                auth = .signedOut
                catalog = nil
            }
        }
    }

    /// Best effort: without the list the pickers still show the saved codes.
    func loadTranslateLanguages() async {
        if appleLanguages.isEmpty {
            appleLanguages = await AppleTranslation.supportedLanguages()
        }
        guard canTranslate, translateLanguages.isEmpty else { return }
        translateLanguages = (try? await client().translateLanguages()) ?? []
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

    /// Moves a saved legacy default to the current one, carrying the session token over:
    /// tokens are signed by the server secret, not bound to a host, so the user stays signed in.
    private func migrateLegacyServer() {
        let saved = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard Self.legacyServers.contains(saved) else { return }
        let oldHost = host
        serverURL = Self.defaultServer
        defaults.removeObject(forKey: Keys.server)
        if keychain.token(for: host) == nil, let token = keychain.token(for: oldHost) {
            try? keychain.setToken(token, for: host)
        }
        keychain.deleteToken(for: oldHost)
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

/// Settings for ⌃⌥Z. Codes are Google Translate language codes.
struct TranslateOptions: Equatable {
    /// Translate into this language.
    var target: String
    /// When the text is already in `target`, translate into this one instead. Nil: show it unchanged.
    var alternate: String?
    /// The engine chosen in Settings. Without Google (demo, signed out, no server key) Apple is used anyway.
    var engine: TranslateEngine

    init(target: String = TranslateOptions.systemLanguage, alternate: String? = nil, engine: TranslateEngine = .google) {
        self.target = target
        self.alternate = alternate
        self.engine = engine
    }

    init(from defaults: UserDefaults) {
        self.init(
            target: defaults.string(forKey: "translateTarget") ?? Self.systemLanguage,
            alternate: defaults.string(forKey: "translateAlternate"),
            engine: defaults.string(forKey: "translateEngine").flatMap(TranslateEngine.init(rawValue:)) ?? .google
        )
    }

    /// The language last picked in the popup becomes the default. The fallback stays unless it is now the same language.
    mutating func remember(target code: String) {
        target = code
        if alternate == code { alternate = nil }
    }

    func save(to defaults: UserDefaults) {
        defaults.set(target, forKey: "translateTarget")
        defaults.set(alternate, forKey: "translateAlternate")
        defaults.set(engine.rawValue, forKey: "translateEngine")
    }

    /// The Mac's first preferred language, e.g. "en" or "de".
    static var systemLanguage: String {
        Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
    }
}
