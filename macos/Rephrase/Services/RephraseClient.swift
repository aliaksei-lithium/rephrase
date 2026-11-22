import Foundation

/// Talks to the Rephrase Pages Functions with a Bearer token.
struct RephraseClient {
    let baseURL: URL
    let token: String?
    var session: URLSession = .shared

    func login(password: String) async throws -> LoginResponse {
        try await send("api/auth/login", method: "POST", body: ["password": password], authorized: false)
    }

    /// A public demo session: no password, the free Gemma model only, with a shared daily limit.
    func startDemo() async throws -> LoginResponse {
        try await send("api/auth/demo", method: "POST", authorized: false)
    }

    func me() async throws -> MeResponse {
        try await send("api/auth/me")
    }

    func catalog() async throws -> Catalog {
        try await send("api/models")
    }

    /// Streams the rewrite. Cancelling the consuming task closes the connection.
    func rephrase(_ body: RephraseRequest) -> AsyncThrowingStream<RephraseEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try makeRequest("api/rephrase", method: "POST", body: body)
                    request.timeoutInterval = 120
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw APIError.from(status: status, data: data)
                    }
                    for try await line in bytes.lines {
                        guard let event = SSEParser.event(from: line) else { continue }
                        if case .failure(let message) = event { throw APIError.message(message) }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One JSON response; used by quick replace, where nothing is shown while the text arrives.
    func rephraseOnce(_ body: RephraseRequest) async throws -> RephraseResult {
        var body = body
        body.stream = false
        var request = try makeRequest("api/rephrase", method: "POST", body: body)
        request.timeoutInterval = 120
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError.from(status: status, data: data)
        }
        return try Self.decoder.decode(RephraseResult.self, from: data)
    }

    /// Languages Google Translate supports. Fails with 503 when the server has no Google key.
    func translateLanguages() async throws -> [TranslateLanguage] {
        struct Body: Decodable { let languages: [TranslateLanguage] }
        let body: Body = try await send("api/translate")
        return body.languages
    }

    /// Translates plain text; the source language is detected by Google.
    func translate(_ body: TranslateRequest) async throws -> TranslateResult {
        let request = try makeRequest("api/translate", method: "POST", body: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError.from(status: status, data: data)
        }
        return try Self.decoder.decode(TranslateResult.self, from: data)
    }

    private func makeRequest(_ path: String, method: String, body: (some Encodable)?, authorized: Bool = true) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        if authorized, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send<T: Decodable>(_ path: String, method: String = "GET", body: [String: String]? = nil, authorized: Bool = true) async throws -> T {
        let request = try makeRequest(path, method: method, body: body, authorized: authorized)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError.from(status: status, data: data)
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let parsed = try? Date(value, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true))
            guard let date = parsed ?? (try? Date(value, strategy: .iso8601)) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(value)"))
            }
            return date
        }
        return decoder
    }()
}

/// POST /api/rephrase body. Selections from other apps are plain text.
struct RephraseRequest: Encodable, Equatable {
    var text: String
    var mode: String
    var style: String
    var tone: String
    var language: String
    var model: String?
    var format = "plain"
    var stream = true

    init(text: String, options: RephraseOptions, model: String?) {
        self.text = text
        mode = options.mode
        style = options.style
        tone = options.tone
        language = options.language
        self.model = model
    }
}

/// POST /api/rephrase with stream: false
struct RephraseResult: Decodable {
    let text: String
    let model: String?
}

/// POST /api/translate body. `alternate` is used when the text is already in `target`.
struct TranslateRequest: Encodable, Equatable {
    var text: String
    var target: String
    var alternate: String?
}

/// POST /api/translate. `source` is the detected language, `target` the one actually used.
struct TranslateResult: Decodable, Equatable {
    let text: String
    let source: String?
    let target: String
}

struct TranslateLanguage: Decodable, Equatable, Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }

    /// Shown until the server's list has loaded (or when it can't translate yet).
    static let common: [TranslateLanguage] = ["ar", "zh-CN", "cs", "nl", "en", "fr", "de", "it", "ja", "ko", "pl", "pt", "ru", "es", "tr", "uk"]
        .map { TranslateLanguage(code: $0, name: Locale(identifier: "en").localizedString(forIdentifier: $0) ?? $0) }
        .sorted { $0.name < $1.name }
}

struct LoginResponse: Decodable {
    let token: String
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
    }
}

struct MeResponse: Decodable {
    let authenticated: Bool
    let expiresAt: Date?
    /// The session is a demo one. Missing on servers without the demo.
    var demo: Bool?
    var demoAvailable: Bool?

    enum CodingKeys: String, CodingKey {
        case authenticated, demo
        case expiresAt = "expires_at"
        case demoAvailable = "demo_available"
    }
}

/// GET /api/models
struct Catalog: Decodable, Equatable {
    struct Model: Decodable, Equatable, Identifiable {
        let id: String
        let label: String?
        let hint: String?
        let provider: String?

        var title: String { label ?? id }
    }

    let models: [Model]
    let defaultModel: String?
    let modes: [String]
    let styles: [String]
    let tones: [String]
    let languages: [String]
    let formats: [String]?
    /// Set for demo sessions, which have a shorter text limit.
    var demo: Bool?
    var maxChars: Int?
    /// The server has a Google Translate key. Missing on older servers.
    var translate: Bool?

    enum CodingKeys: String, CodingKey {
        case models, modes, styles, tones, languages, formats, demo, translate
        case defaultModel = "default"
        case maxChars = "max_chars"
    }
}

enum APIError: LocalizedError, Equatable {
    case message(String)
    case unauthorized(String)

    static func from(status: Int, data: Data) -> APIError {
        struct Body: Decodable { let error: String? }
        let text = (try? JSONDecoder().decode(Body.self, from: data))?.error
            ?? HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        return status == 401 ? .unauthorized(text) : .message(text)
    }

    var errorDescription: String? {
        switch self {
        case .message(let text), .unauthorized(let text): text
        }
    }
}
