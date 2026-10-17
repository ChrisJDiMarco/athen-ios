import Foundation

protocol TimelineServicing {
    func fetchTimeline(issueId: String) async throws -> [CivicTimelineEvent]
    func exportIssuesCSV(scope: String?, stateCode: String?, q: String?) async throws -> Data
}

struct HTTPTimelineService: TimelineServicing {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = AthenURLSession.shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchTimeline(issueId: String) async throws -> [CivicTimelineEvent] {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/issues/\(issueId)/timeline"))
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        try ensure2xx(response: response, data: data)
        return try JSONDecoder().decode(CivicTimelineResponse.self, from: data).events
    }

    func exportIssuesCSV(scope: String?, stateCode: String?, q: String?) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/issues/export.csv"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []
        if let scope, !scope.isEmpty { items.append(URLQueryItem(name: "scope", value: scope)) }
        if let stateCode, !stateCode.isEmpty { items.append(URLQueryItem(name: "stateCode", value: stateCode)) }
        if let q, !q.isEmpty { items.append(URLQueryItem(name: "q", value: q)) }
        components.queryItems = items.isEmpty ? nil : items
        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        req.setValue("text/csv", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        try ensure2xx(response: response, data: data)
        return data
    }

    private func ensure2xx(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CivicFilingError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CivicFilingError.server(status: http.statusCode, message: body.isEmpty ? "Request failed." : String(body.prefix(180)))
        }
    }
}

struct MockTimelineService: TimelineServicing {
    func fetchTimeline(issueId _: String) async throws -> [CivicTimelineEvent] { [] }
    func exportIssuesCSV(scope _: String?, stateCode _: String?, q _: String?) async throws -> Data {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to export.")
    }
}
