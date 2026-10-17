import Foundation

protocol NewsServicing {
    func background(for issue: CivicIssue, stateCode: String?) async throws -> BackgroundReading?
}

struct HTTPNewsService: NewsServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 25) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func background(for issue: CivicIssue, stateCode: String?) async throws -> BackgroundReading? {
        let url = baseURL.appendingPathComponent("v1/issue/background")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = BackgroundRequest(
            issueTitle: issue.title,
            jurisdiction: issue.jurisdiction,
            scope: BackgroundRequest.scopeString(for: issue.scope),
            stateCode: stateCode
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CivicFilingError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackgroundResponse.self, from: data)
        guard let summary = payload.summary, !summary.isEmpty, let generated = payload.generatedAt else {
            return nil
        }
        return BackgroundReading(
            summary: summary,
            citations: payload.citations,
            generatedAt: generated
        )
    }
}

struct MockNewsService: NewsServicing {
    func background(for issue: CivicIssue, stateCode _: String?) async throws -> BackgroundReading? {
        try await Task.sleep(nanoseconds: 600_000_000)
        switch issue.scope {
        case .federal:
            return BackgroundReading(
                summary: "House appropriators have signaled bipartisan support for preserving formula-grant transit funding, though committee Republicans flagged a possible 5% trim during markup [1]. Transit agencies in mid-sized metros say even small cuts would translate into reduced service hours [2].",
                citations: [
                    BackgroundCitation(source: "rollcall.com", title: "Appropriators close to deal on transit operating funds", url: "https://example.com/rollcall", snippet: "Markup expected this week with a possible trim of operating funds…"),
                    BackgroundCitation(source: "apnews.com", title: "Transit agencies brace for tight federal year", url: "https://example.com/apnews", snippet: "Mid-sized agencies say a 5% cut would shorten weekend service…")
                ],
                generatedAt: .now
            )
        case .localPhilly:
            return BackgroundReading(
                summary: "Local reporting frames the corridor rezoning as the largest land-use vote of the session, with both housing advocates and a handful of civic associations weighing in [1]. The Inquirer notes the committee added a transit-adjacent overlay that narrows what can be built off-corridor [2].",
                citations: [
                    BackgroundCitation(source: "billypenn.com", title: "Broad Street rezoning hits Council this week", url: "https://example.com/billypenn", snippet: "Council members say the package is the largest land-use vote of the session…"),
                    BackgroundCitation(source: "inquirer.com", title: "Inquirer: rezoning amendment narrows off-corridor uses", url: "https://example.com/inquirer", snippet: "An overlay added in committee restricts off-corridor density…")
                ],
                generatedAt: .now
            )
        case .state:
            return nil
        }
    }
}

private struct BackgroundRequest: Encodable {
    let issueTitle: String
    let jurisdiction: String
    let scope: String
    let stateCode: String?

    static func scopeString(for scope: JurisdictionScope) -> String {
        switch scope {
        case .federal: "federal"
        case .state: "state"
        case .localPhilly: "local-philly"
        }
    }
}

private struct BackgroundResponse: Decodable {
    let summary: String?
    let citations: [BackgroundCitation]
    let generatedAt: Date?
}

private extension JurisdictionScope {
    enum DecodingError: Error { case unknownScope }
}
