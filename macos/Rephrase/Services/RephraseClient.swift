import Foundation

/// Talks to the Rephrase Pages Functions with a Bearer token.
struct RephraseClient {
    let baseURL: URL
    let token: String?
    var session: URLSession = .shared

    func login(password: String) async throws -> LoginResponse {
        try await send("api/auth/login", method: "POST", body: ["password": password], authorized: false)
    }

    func me() async throws -> MeResponse {
        try await send("api/auth/me")
    }

    func catalog() async throws -> Catalog {
        try await send("api/models")
    }

    private func send<T: Decodable>(_ path: String, method: String = "GET", body: [String: String]? = nil, authorized: Bool = true) async throws -> T {
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

    enum CodingKeys: String, CodingKey {
        case authenticated
        case expiresAt = "expires_at"
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

    enum CodingKeys: String, CodingKey {
        case models, modes, styles, tones, languages, formats
        case defaultModel = "default"
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
