import Foundation

/// Per-source result returned by the backend orchestrator.
struct RefreshSourceReport: Identifiable, Equatable, Hashable, Decodable {
    let id: String
    let name: String
    let status: String
    let inspected: Int
    let inserted: Int
    let updated: Int
    let skippedReason: String?
    let error: String?
    let durationMs: Int
}

struct RefreshReport: Equatable, Hashable, Decodable {
    let startedAt: Date
    let finishedAt: Date
    let durationMs: Int
    let totalInserted: Int
    let totalUpdated: Int
    let totalIssues: Int
    let sources: [RefreshSourceReport]
}

protocol RefreshServicing {
    func triggerRefresh() async throws -> RefreshReport
}

struct HTTPRefreshService: RefreshServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 60) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func triggerRefresh() async throws -> RefreshReport {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/refresh"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(RefreshErrorResponse.self, from: data))?.error.message
            throw CivicFilingError.server(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: message ?? "Refresh failed.")
        }

        let decoder = JSONDecoder()
        // Backend emits both plain ISO-8601 ("2026-05-19T21:00:00Z") and
        // fractional-second variants ("2026-05-19T21:00:00.605Z"). Apple's
        // default `.iso8601` strategy rejects the latter, so handle both.
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let raw = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }
            if let date = ISO8601DateFormatter().date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(raw)")
        }
        return try decoder.decode(RefreshReport.self, from: data)
    }
}

struct MockRefreshService: RefreshServicing {
    func triggerRefresh() async throws -> RefreshReport {
        try await Task.sleep(nanoseconds: 400_000_000)
        return RefreshReport(
            startedAt: .now,
            finishedAt: .now,
            durationMs: 0,
            totalInserted: 0,
            totalUpdated: 0,
            totalIssues: 0,
            sources: []
        )
    }
}

private struct RefreshErrorResponse: Decodable {
    let error: ErrorBody
    struct ErrorBody: Decodable { let code: String; let message: String }
}
