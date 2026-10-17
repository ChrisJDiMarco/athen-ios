import Foundation

protocol SourcesServicing {
    func fetchSources() async throws -> CivicSourcesSnapshot
}

struct HTTPSourcesService: SourcesServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 15) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func fetchSources() async throws -> CivicSourcesSnapshot {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/sources"), timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CivicFilingError.invalidResponse
        }
        let payload = try JSONDecoder().decode(SourcesResponse.self, from: data)
        let generated = ISO8601DateFormatter().date(from: payload.generatedAtISO) ?? .now
        return CivicSourcesSnapshot(
            generatedAt: generated,
            sources: payload.sources,
            registered: payload.totals.registered,
            activeHosts: payload.totals.activeHosts,
            totalIssues: payload.totals.issues
        )
    }
}

struct MockSourcesService: SourcesServicing {
    func fetchSources() async throws -> CivicSourcesSnapshot {
        // Empty snapshot — Mock mode shows "Connect a backend to see sources".
        CivicSourcesSnapshot(generatedAt: .now, sources: [], registered: 0, activeHosts: 0, totalIssues: 0)
    }
}

private struct SourcesResponse: Decodable {
    let generatedAtISO: String
    let sources: [CivicSourceDescriptor]
    let totals: Totals

    struct Totals: Decodable {
        let registered: Int
        let activeHosts: Int
        let issues: Int
    }
}
