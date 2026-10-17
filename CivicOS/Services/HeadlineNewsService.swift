import Foundation

/// Headline fetched from the backend's `/v1/news` endpoint. Backend pulls from
/// Google News RSS (free, no key) scoped to the user's city + state, with a
/// short server-side cache.
struct NewsHeadline: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let title: String
    let link: String
    let source: String
    let publishedISO: String?
    let snippet: String?

    var publishedAt: Date? {
        guard let iso = publishedISO else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
}

/// Bundle returned by /v1/news when `?summary=1` is set — headlines plus
/// a Claude-generated 2-3 sentence "quick glance" of today's stories.
struct NewsFeed: Equatable {
    let items: [NewsHeadline]
    let summary: String?
}

/// Fetches headlines for the Home → News mode.
struct NewsService {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = AthenURLSession.shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchNews(
        city: String?,
        state: String?,
        force: Bool = false,
        includeSummary: Bool = false,
    ) async throws -> NewsFeed {
        var comps = URLComponents(url: baseURL.appendingPathComponent("v1/news"), resolvingAgainstBaseURL: false)!
        var qs: [URLQueryItem] = []
        if let city = city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            qs.append(.init(name: "city", value: city))
        }
        if let state = state?.trimmingCharacters(in: .whitespacesAndNewlines), !state.isEmpty {
            qs.append(.init(name: "state", value: state))
        }
        if force { qs.append(.init(name: "fresh", value: "1")) }
        if includeSummary { qs.append(.init(name: "summary", value: "1")) }
        comps.queryItems = qs.isEmpty ? nil : qs

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        // Summary requests can take ~3-5s due to the Claude call; bump
        // the timeout so the in-app spinner doesn't time out first.
        req.timeoutInterval = includeSummary ? 35 : 20
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        struct Wrap: Decodable {
            let items: [NewsHeadline]
            let summary: String?
        }
        let wrap = (try? JSONDecoder().decode(Wrap.self, from: data)) ?? Wrap(items: [], summary: nil)
        return NewsFeed(items: wrap.items, summary: wrap.summary)
    }
}
