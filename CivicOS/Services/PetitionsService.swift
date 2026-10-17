import Foundation

protocol PetitionsServicing {
    func list(entityId: String, filter: PetitionFilter) async throws -> CivicPetitionListResponse
    func detail(id: String, entityId: String) async throws -> CivicPetitionDetailResponse
    func create(entityId: String, input: PetitionCreateInput) async throws -> CivicPetition
    func sign(id: String, entityId: String, name: String, zip: String, comment: String?) async throws -> CivicPetition
    func unsign(id: String, entityId: String) async throws -> CivicPetition?
    func deliver(id: String, entityId: String) async throws -> CivicPetitionDeliveryResult
    func delete(id: String, entityId: String) async throws
}

struct PetitionFilter: Equatable, Hashable {
    var status: CivicPetition.Status?
    var zip: String?
    var topicId: String?
    var mine: Bool

    static let everything = PetitionFilter(status: nil, zip: nil, topicId: nil, mine: false)
    static let openOnly = PetitionFilter(status: .open, zip: nil, topicId: nil, mine: false)
    static let mine = PetitionFilter(status: nil, zip: nil, topicId: nil, mine: true)
}

struct PetitionCreateInput: Encodable {
    let title: String
    let ask: String
    let body: String
    let creatorDisplayName: String
    let attachedIssueId: String?
    let zip: String?
    let threshold: Int?
    let deadlineISO: String?
    let visibility: String?
    let targets: [TargetInput]?

    struct TargetInput: Encodable {
        let officialName: String
        let jurisdiction: String
        let email: String?
        let contactFormURL: String?
        let channel: String
    }
}

struct HTTPPetitionsService: PetitionsServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func list(entityId: String, filter: PetitionFilter) async throws -> CivicPetitionListResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/petitions"), resolvingAgainstBaseURL: false)!
        var query: [URLQueryItem] = []
        if let status = filter.status { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if let zip = filter.zip { query.append(URLQueryItem(name: "zip", value: zip)) }
        if let topicId = filter.topicId { query.append(URLQueryItem(name: "topicId", value: topicId)) }
        if filter.mine { query.append(URLQueryItem(name: "mine", value: "true")) }
        components.queryItems = query.isEmpty ? nil : query

        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(entityId, forHTTPHeaderField: "x-athen-entity")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(CivicPetitionListResponse.self, from: data)
    }

    func detail(id: String, entityId: String) async throws -> CivicPetitionDetailResponse {
        let url = baseURL.appendingPathComponent("v1/petitions/\(id)")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(entityId, forHTTPHeaderField: "x-athen-entity")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(CivicPetitionDetailResponse.self, from: data)
    }

    func create(entityId: String, input: PetitionCreateInput) async throws -> CivicPetition {
        let url = baseURL.appendingPathComponent("v1/petitions")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(entityId, forHTTPHeaderField: "x-athen-entity")
        request.httpBody = try JSONEncoder().encode(input)
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(CreatedWrapper.self, from: data).petition
    }

    func sign(id: String, entityId: String, name: String, zip: String, comment: String?) async throws -> CivicPetition {
        let url = baseURL.appendingPathComponent("v1/petitions/\(id)/sign")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(entityId, forHTTPHeaderField: "x-athen-entity")
        var payload: [String: String] = ["name": name, "zip": zip]
        if let comment, !comment.isEmpty { payload["comment"] = comment }
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(SignWrapper.self, from: data).petition
    }

    func unsign(id: String, entityId: String) async throws -> CivicPetition? {
        let url = baseURL.appendingPathComponent("v1/petitions/\(id)/signature")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(entityId, forHTTPHeaderField: "x-athen-entity")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(UnsignWrapper.self, from: data).petition
    }

    func deliver(id: String, entityId: String) async throws -> CivicPetitionDeliveryResult {
        let url = baseURL.appendingPathComponent("v1/petitions/\(id)/deliver")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(entityId, forHTTPHeaderField: "x-athen-entity")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(DeliverWrapper.self, from: data).delivery
    }

    func delete(id: String, entityId: String) async throws {
        let url = baseURL.appendingPathComponent("v1/petitions/\(id)")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(entityId, forHTTPHeaderField: "x-athen-entity")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
    }

    private func ensureSuccess(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CivicFilingError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            let msg = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
            throw CivicFilingError.server(status: http.statusCode, message: msg ?? "Petition request failed.")
        }
    }
}

struct MockPetitionsService: PetitionsServicing {
    func list(entityId _: String, filter _: PetitionFilter) async throws -> CivicPetitionListResponse {
        CivicPetitionListResponse(
            items: [],
            stats: .init(total: 0, open: 0, delivered: 0, expired: 0, totalSignatures: 0),
            viewer: nil
        )
    }
    func detail(id _: String, entityId _: String) async throws -> CivicPetitionDetailResponse {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to view petitions.")
    }
    func create(entityId _: String, input _: PetitionCreateInput) async throws -> CivicPetition {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to start a petition.")
    }
    func sign(id _: String, entityId _: String, name _: String, zip _: String, comment _: String?) async throws -> CivicPetition {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to sign petitions.")
    }
    func unsign(id _: String, entityId _: String) async throws -> CivicPetition? { nil }
    func deliver(id _: String, entityId _: String) async throws -> CivicPetitionDeliveryResult {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to deliver petitions.")
    }
    func delete(id _: String, entityId _: String) async throws {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to delete petitions.")
    }
}

private struct CreatedWrapper: Decodable { let petition: CivicPetition }
private struct SignWrapper: Decodable { let petition: CivicPetition }
private struct UnsignWrapper: Decodable { let petition: CivicPetition? }
private struct DeliverWrapper: Decodable {
    let delivery: CivicPetitionDeliveryResult
    let petition: CivicPetition?
}
private struct ErrorEnvelope: Decodable {
    let error: Body
    struct Body: Decodable { let code: String; let message: String }
}
