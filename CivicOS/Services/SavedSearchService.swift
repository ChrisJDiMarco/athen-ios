import Foundation

protocol SavedSearchServicing {
    func list() async throws -> [CivicSavedSearch]
    func create(name: String, query: String, scope: CivicSavedSearch.Scope, stateCode: String?, alertsEnabled: Bool) async throws -> CivicSavedSearchCreateResponse
    func update(id: String, patch: SavedSearchPatch) async throws -> CivicSavedSearch
    func delete(id: String) async throws
}

/// Sparse patch object for PUT /v1/saved-searches/:id — every field is
/// optional so callers only send what changed.
struct SavedSearchPatch: Encodable {
    var name: String?
    var query: String?
    var scope: CivicSavedSearch.Scope?
    var stateCode: String?
    var alertsEnabled: Bool?
    var lastSeenAt: String?
}

struct HTTPSavedSearchService: SavedSearchServicing {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = AthenURLSession.shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func list() async throws -> [CivicSavedSearch] {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/saved-searches"))
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        try ensure2xx(response: response, data: data)
        return try JSONDecoder().decode(CivicSavedSearchListResponse.self, from: data).items
    }

    func create(name: String, query: String, scope: CivicSavedSearch.Scope, stateCode: String?, alertsEnabled: Bool) async throws -> CivicSavedSearchCreateResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/saved-searches"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        struct Body: Encodable {
            let name: String
            let query: String
            let scope: String
            let stateCode: String?
            let alertsEnabled: Bool
        }
        let body = Body(name: name, query: query, scope: scope.rawValue, stateCode: stateCode, alertsEnabled: alertsEnabled)
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: req)
        try ensure2xx(response: response, data: data)
        return try JSONDecoder().decode(CivicSavedSearchCreateResponse.self, from: data)
    }

    func update(id: String, patch: SavedSearchPatch) async throws -> CivicSavedSearch {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/saved-searches/\(id)"))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let encoder = JSONEncoder()
        // Default Encodable behavior already omits nil fields for `var x: T?`
        req.httpBody = try encoder.encode(patch)
        let (data, response) = try await session.data(for: req)
        try ensure2xx(response: response, data: data)
        return try JSONDecoder().decode(CivicSavedSearchSingleResponse.self, from: data).search
    }

    func delete(id: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/saved-searches/\(id)"))
        req.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: req)
        try ensure2xx(response: response, data: data)
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

struct MockSavedSearchService: SavedSearchServicing {
    func list() async throws -> [CivicSavedSearch] { [] }
    func create(name _: String, query _: String, scope _: CivicSavedSearch.Scope, stateCode _: String?, alertsEnabled _: Bool) async throws -> CivicSavedSearchCreateResponse {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to save searches.")
    }
    func update(id _: String, patch _: SavedSearchPatch) async throws -> CivicSavedSearch {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to update saved searches.")
    }
    func delete(id _: String) async throws {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to delete saved searches.")
    }
}
