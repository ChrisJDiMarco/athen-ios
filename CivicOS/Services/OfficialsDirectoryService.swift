import Foundation

protocol OfficialsDirectoryServicing {
    func federal() async throws -> [DirectoryOfficial]
    func state(_ stateCode: String) async throws -> [DirectoryOfficial]
    func search(_ query: String) async throws -> [DirectoryOfficial]
    func detail(id: String) async throws -> DirectoryOfficial
}

struct HTTPOfficialsDirectoryService: OfficialsDirectoryServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 45) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func federal() async throws -> [DirectoryOfficial] {
        try await fetchList(at: "v1/officials/federal")
    }

    func state(_ stateCode: String) async throws -> [DirectoryOfficial] {
        try await fetchList(at: "v1/officials/state/\(stateCode.uppercased())")
    }

    func search(_ query: String) async throws -> [DirectoryOfficial] {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/officials/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return try await fetchList(url: components.url!)
    }

    func detail(id: String) async throws -> DirectoryOfficial {
        let url = baseURL.appendingPathComponent("v1/officials/\(id)")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(DirectoryOfficialDetailResponse.self, from: data).official
    }

    private func fetchList(at path: String) async throws -> [DirectoryOfficial] {
        try await fetchList(url: baseURL.appendingPathComponent(path))
    }

    private func fetchList(url: URL) async throws -> [DirectoryOfficial] {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(DirectoryOfficialsResponse.self, from: data).officials
    }

    private func ensureSuccess(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CivicFilingError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            let msg = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
            throw CivicFilingError.server(status: http.statusCode, message: msg ?? "Directory request failed.")
        }
    }
}

struct MockOfficialsDirectoryService: OfficialsDirectoryServicing {
    func federal() async throws -> [DirectoryOfficial] { [] }
    func state(_ stateCode: String) async throws -> [DirectoryOfficial] { [] }
    func search(_ query: String) async throws -> [DirectoryOfficial] { [] }
    func detail(id: String) async throws -> DirectoryOfficial {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to view the directory.")
    }
}

private struct ErrorEnvelope: Decodable {
    let error: Body
    struct Body: Decodable { let code: String; let message: String }
}
