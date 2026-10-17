import Foundation

/// Fetches per-install daily AI quota usage from the backend so the You
/// tab can show transparent "X of Y AI requests left today" copy instead
/// of waiting for an opaque 429 mid-flow.

struct AthenQuotaUsage: Decodable, Identifiable, Hashable {
    let name: String
    let used: Int
    let max: Int
    let remaining: Int

    var id: String { name }

    /// Friendly display label — `claude:brief` → `AI Briefs`.
    var displayLabel: String {
        switch name {
        case "claude:brief":    return "AI briefs"
        case "claude:chat":     return "Assistant messages"
        case "claude:draft":    return "Filing drafts"
        case "claude:plan":     return "Life-event plans"
        case "claude:translate": return "Translations"
        case "elevenlabs:tts":  return "Audio briefings"
        default:
            // Strip the namespace if it's unknown — "x:y" → "y".
            let parts = name.split(separator: ":")
            return parts.last.map { $0.replacingOccurrences(of: "_", with: " ").capitalized } ?? name
        }
    }
}

struct AthenQuotaSnapshot: Decodable {
    let ok: Bool
    let usage: [AthenQuotaUsage]
}

protocol QuotaServicing {
    func fetchUsage() async throws -> [AthenQuotaUsage]
}

final class HTTPQuotaService: QuotaServicing {
    private let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 10) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func fetchUsage() async throws -> [AthenQuotaUsage] {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/quota"))
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let snapshot = try JSONDecoder().decode(AthenQuotaSnapshot.self, from: data)
        return snapshot.usage
    }
}

struct MockQuotaService: QuotaServicing {
    init() {}
    func fetchUsage() async throws -> [AthenQuotaUsage] { [] }
}
