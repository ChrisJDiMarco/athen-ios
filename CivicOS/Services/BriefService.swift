import Foundation

protocol BriefServicing {
    func fetchDigest(stateCode: String?, zip: String?, limit: Int, warm: Bool) async throws -> CivicBriefDigest
    func fetchBrief(issueId: String, force: Bool) async throws -> CivicBriefAnalysis
    func rewriteBrief(issueId: String, audience: BriefAudience) async throws -> String
    func fetchAudioBriefing(stateCode: String?, stateName: String?, zip: String?, duration: Int?, voiceId: String?, focus: String?) async throws -> CivicAudioBriefing
}

extension BriefServicing {
    func fetchBrief(issueId: String) async throws -> CivicBriefAnalysis {
        try await fetchBrief(issueId: issueId, force: false)
    }
}

enum BriefAudience: String, CaseIterable, Identifiable {
    case kid
    case parent
    case landlord
    case neighbor
    case lawyer

    var id: String { rawValue }

    var pillLabel: String {
        switch self {
        case .kid: "I'm 12"
        case .parent: "I'm a parent"
        case .landlord: "I'm a landlord"
        case .neighbor: "30-second"
        case .lawyer: "Legal angle"
        }
    }

    var systemImage: String {
        switch self {
        case .kid: "graduationcap.fill"
        case .parent: "figure.2.and.child.holdinghands"
        case .landlord: "house.fill"
        case .neighbor: "hand.wave.fill"
        case .lawyer: "scale.3d"
        }
    }
}

struct HTTPBriefService: BriefServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 120) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func fetchDigest(stateCode: String?, zip: String?, limit: Int, warm: Bool) async throws -> CivicBriefDigest {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/brief"), resolvingAgainstBaseURL: false)!
        var q: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if warm { q.append(URLQueryItem(name: "warm", value: "true")) }
        if let stateCode { q.append(URLQueryItem(name: "stateCode", value: stateCode)) }
        if let zip { q.append(URLQueryItem(name: "zip", value: zip)) }
        components.queryItems = q

        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(CivicBriefDigest.self, from: data)
    }

    func fetchBrief(issueId: String, force: Bool) async throws -> CivicBriefAnalysis {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/brief/\(issueId)"), resolvingAgainstBaseURL: false)!
        if force {
            components.queryItems = [URLQueryItem(name: "force", value: "true")]
        }
        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        let wrapped = try JSONDecoder().decode(BriefResponse.self, from: data)
        return wrapped.brief
    }

    func rewriteBrief(issueId: String, audience: BriefAudience) async throws -> String {
        let url = baseURL.appendingPathComponent("v1/brief/\(issueId)/rewrite")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["audience": audience.rawValue])

        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        let wrapped = try JSONDecoder().decode(RewriteResponse.self, from: data)
        return wrapped.text
    }

    func fetchAudioBriefing(stateCode: String?, stateName: String?, zip: String?, duration: Int?, voiceId: String?, focus: String?) async throws -> CivicAudioBriefing {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/briefing/audio"), resolvingAgainstBaseURL: false)!
        var q: [URLQueryItem] = []
        if let stateCode { q.append(URLQueryItem(name: "stateCode", value: stateCode)) }
        if let stateName { q.append(URLQueryItem(name: "stateName", value: stateName)) }
        if let zip { q.append(URLQueryItem(name: "zip", value: zip)) }
        if let duration { q.append(URLQueryItem(name: "duration", value: String(duration))) }
        if let voiceId, !voiceId.isEmpty { q.append(URLQueryItem(name: "voiceId", value: voiceId)) }
        if let focus, !focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            q.append(URLQueryItem(name: "focus", value: focus))
        }
        components.queryItems = q.isEmpty ? nil : q

        var request = URLRequest(url: components.url!, timeoutInterval: 90)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(CivicAudioBriefing.self, from: data)
    }

    private func ensureSuccess(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CivicFilingError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            let message = (try? JSONDecoder().decode(BriefErrorResponse.self, from: data))?.error.message
            throw CivicFilingError.server(status: http.statusCode, message: message ?? "Brief request failed.")
        }
    }
}

struct MockBriefService: BriefServicing {
    func fetchDigest(stateCode _: String?, zip _: String?, limit _: Int, warm _: Bool) async throws -> CivicBriefDigest {
        throw CivicFilingError.server(status: 0, message: "Connect a backend from Radar → profile → AI backend to load briefs.")
    }
    func fetchBrief(issueId _: String, force _: Bool) async throws -> CivicBriefAnalysis {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to generate briefs.")
    }
    func rewriteBrief(issueId _: String, audience _: BriefAudience) async throws -> String {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to rewrite briefs.")
    }
    func fetchAudioBriefing(stateCode _: String?, stateName _: String?, zip _: String?, duration _: Int?, voiceId _: String?, focus _: String?) async throws -> CivicAudioBriefing {
        throw CivicFilingError.server(status: 0, message: "Connect a backend for audio briefings.")
    }
}

private struct BriefResponse: Decodable {
    let brief: CivicBriefAnalysis
}

private struct RewriteResponse: Decodable {
    let audience: String
    let text: String
}

private struct BriefErrorResponse: Decodable {
    let error: ErrorBody
    struct ErrorBody: Decodable { let code: String; let message: String }
}
