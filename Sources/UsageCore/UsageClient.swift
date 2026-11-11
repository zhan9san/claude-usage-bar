import Foundation

/// Fetches usage by sending a minimal Messages API request and reading the
/// rate-limit headers from the response.
public struct UsageClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// Setup tokens only get usable responses from Haiku models; other models
    /// return a bare 429 without usage headers.
    public static let defaultModel = "claude-haiku-4-5-20251001"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(token: String, model: String) async throws -> UsageSnapshot {
        let request = try Self.makeRequest(token: token, model: model)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UsageError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.noUsageHeaders
        }
        return try Self.interpret(
            statusCode: http.statusCode,
            headers: RateLimitParser.headers(from: http),
            body: data,
            now: Date()
        )
    }

    public static func makeRequest(token: String, model: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(
            ProbeBody(model: model, maxTokens: 1, messages: [.init(role: "user", content: "hi")])
        )
        return request
    }

    /// Maps a raw response to a snapshot or a typed error. Kept separate from
    /// networking so it can be unit tested.
    public static func interpret(
        statusCode: Int,
        headers: [String: String],
        body: Data,
        now: Date
    ) throws -> UsageSnapshot {
        let snapshot = RateLimitParser.parse(headers: headers, now: now)
        switch statusCode {
        case 200..<300:
            guard let snapshot else { throw UsageError.noUsageHeaders }
            return snapshot
        case 429:
            // At the real limit the usage headers are still present, and that
            // is exactly the moment the user wants to see them.
            guard let snapshot else { throw UsageError.rejectedWithoutUsage }
            return snapshot
        case 401, 403:
            throw UsageError.unauthorized(status: statusCode, message: apiMessage(from: body))
        case 400, 404:
            throw UsageError.badRequest(status: statusCode, message: apiMessage(from: body))
        default:
            throw UsageError.server(status: statusCode, message: apiMessage(from: body))
        }
    }

    static func apiMessage(from body: Data) -> String? {
        struct Envelope: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        return (try? JSONDecoder().decode(Envelope.self, from: body))?.error?.message
    }
}

struct ProbeBody: Codable, Equatable {
    struct Message: Codable, Equatable {
        let role: String
        let content: String
    }

    let model: String
    let maxTokens: Int
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
    }
}
