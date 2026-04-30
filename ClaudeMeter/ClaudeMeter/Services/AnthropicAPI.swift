import Foundation

enum AnthropicAPI {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let oauthBetaHeader = "oauth-2025-04-20"

    static var userAgent: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        return "claude-meter/\(v) (macOS)"
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let d = withFractional.date(from: str) { return d }
            if let d = plain.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "expected ISO 8601 date, got \(str)"
            )
        }
        return decoder
    }()

    enum APIError: Error {
        /// 401 — token rejected. Caller should force-refresh and retry once.
        case unauthorized
        /// 403 — usually a scope mismatch. Body string included for diagnostics.
        case forbidden(body: String)
        /// 404 — endpoint removed or moved. claude-meter likely needs an update.
        case notFound
        /// 5xx — Anthropic-side issue. Caller should back off and retry later.
        case server(status: Int)
        /// HTTP succeeded but body didn't decode to UsageSnapshot.
        case decoding(underlying: any Error)
        /// Anything else (3xx, 4xx other than the above).
        case unexpected(status: Int, body: String)
        /// URLSession-level failure (offline, DNS, TLS, etc).
        case network(underlying: any Error)
        /// URLResponse wasn't an HTTPURLResponse.
        case invalidResponse
    }

    static func fetchUsage(token: String, session: URLSession = .shared) async throws -> UsageSnapshot {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(oauthBetaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            do {
                return try decoder.decode(UsageSnapshot.self, from: data)
            } catch {
                throw APIError.decoding(underlying: error)
            }
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden(body: String(decoding: data, as: UTF8.self))
        case 404:
            throw APIError.notFound
        case 500..<600:
            throw APIError.server(status: http.statusCode)
        default:
            throw APIError.unexpected(
                status: http.statusCode,
                body: String(decoding: data, as: UTF8.self)
            )
        }
    }
}
