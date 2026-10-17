import Foundation

protocol VoterRailServicing {
    func listElections() async throws -> CivicElectionsResponse
    func pollingPlace(zip: String) async throws -> CivicPollingPlaceResponse
    func ballot(zip: String, electionId: String?) async throws -> CivicBallotResponse
    func registration(stateCode: String) async throws -> StateRegistrationInfo
    func scorecard(filings: [ScorecardFilingInput]) async throws -> RepScorecardResponse
}

struct ScorecardFilingInput: Encodable {
    let issueId: String
    let issueTitle: String
    let position: String
    let filedAtISO: String
    let officialName: String
}

struct HTTPVoterRailService: VoterRailServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 45) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func listElections() async throws -> CivicElectionsResponse {
        let url = baseURL.appendingPathComponent("v1/voter/elections")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(CivicElectionsResponse.self, from: data)
    }

    func pollingPlace(zip: String) async throws -> CivicPollingPlaceResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/voter/polling-place"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "zip", value: zip)]
        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(CivicPollingPlaceResponse.self, from: data)
    }

    func ballot(zip: String, electionId: String?) async throws -> CivicBallotResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/voter/ballot"), resolvingAgainstBaseURL: false)!
        var q: [URLQueryItem] = [URLQueryItem(name: "zip", value: zip)]
        if let electionId { q.append(URLQueryItem(name: "electionId", value: electionId)) }
        components.queryItems = q
        var request = URLRequest(url: components.url!, timeoutInterval: 90)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(CivicBallotResponse.self, from: data)
    }

    func registration(stateCode: String) async throws -> StateRegistrationInfo {
        let url = baseURL.appendingPathComponent("v1/voter/registration/\(stateCode.uppercased())")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(CivicRegistrationResponse.self, from: data).registration
    }

    func scorecard(filings: [ScorecardFilingInput]) async throws -> RepScorecardResponse {
        let url = baseURL.appendingPathComponent("v1/voter/scorecard")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["filings": filings])
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(RepScorecardResponse.self, from: data)
    }

    private func ensureSuccess(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CivicFilingError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            let msg = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
            throw CivicFilingError.server(status: http.statusCode, message: msg ?? "Voter request failed.")
        }
    }
}

struct MockVoterRailService: VoterRailServicing {
    func listElections() async throws -> CivicElectionsResponse {
        CivicElectionsResponse(enabled: false, elections: [], notice: "Connect a backend to load elections.")
    }
    func pollingPlace(zip _: String) async throws -> CivicPollingPlaceResponse {
        CivicPollingPlaceResponse(enabled: false, pollingPlaces: [], earlyVoteSites: nil, dropOffLocations: nil, election: nil, state: nil, notice: "Connect a backend to look up polling places.")
    }
    func ballot(zip _: String, electionId _: String?) async throws -> CivicBallotResponse {
        CivicBallotResponse(enabled: false, ballot: nil, pollingPlaces: nil, state: nil, notice: "Connect a backend to load your sample ballot.")
    }
    func registration(stateCode _: String) async throws -> StateRegistrationInfo {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to look up registration info.")
    }
    func scorecard(filings _: [ScorecardFilingInput]) async throws -> RepScorecardResponse {
        RepScorecardResponse(scorecards: [], notFiledYet: [], generatedAtISO: ISO8601DateFormatter().string(from: .now))
    }
}

private struct ErrorEnvelope: Decodable {
    let error: Body
    struct Body: Decodable { let code: String; let message: String }
}
