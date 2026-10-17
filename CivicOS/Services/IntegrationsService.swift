import Foundation

protocol IntegrationsServicing {
    func fetchCatalog() async throws -> CivicIntegrationCatalog
    func fetchStatus(entityId: String) async throws -> CivicIntegrationStatusList
    func connect(entityId: String, appName: String) async throws -> CivicIntegrationConnectResult
    func disconnect(connectionId: String) async throws
    func sendGmail(entityId: String, to: String, subject: String, body: String) async throws
    func runAutomation(entityId: String, automation: String, input: AutomationInputPayload) async throws
}

/// Mirrors the backend's AutomationInput shape. All fields optional; only
/// the ones relevant to the chosen automation get filled in.
struct AutomationInputPayload: Encodable {
    var title: String?
    var startISO: String?
    var endISO: String?
    var notes: String?
    var location: String?
    var databaseId: String?
    var pageTitle: String?
    var properties: [String: PropertyValue]?
    var channel: String?
    var text: String?
    var body: String?
    var hashtags: [String]?
    var to: String?
    var subject: String?

    enum PropertyValue: Encodable {
        case string(String)
        case number(Double)
        case rich([RichTextNode])

        struct RichTextNode: Encodable {
            let text: TextValue
            struct TextValue: Encodable { let content: String }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .string(let s): try c.encode(s)
            case .number(let n): try c.encode(n)
            case .rich(let nodes): try c.encode(nodes)
            }
        }
    }
}

struct HTTPIntegrationsService: IntegrationsServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func fetchCatalog() async throws -> CivicIntegrationCatalog {
        let url = baseURL.appendingPathComponent("v1/integrations/catalog")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(CivicIntegrationCatalog.self, from: data)
    }

    func fetchStatus(entityId: String) async throws -> CivicIntegrationStatusList {
        let url = baseURL.appendingPathComponent("v1/integrations")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(entityId, forHTTPHeaderField: "x-athen-entity")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(CivicIntegrationStatusList.self, from: data)
    }

    func connect(entityId: String, appName: String) async throws -> CivicIntegrationConnectResult {
        let url = baseURL.appendingPathComponent("v1/integrations/connect")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(entityId, forHTTPHeaderField: "x-athen-entity")
        request.httpBody = try JSONEncoder().encode(["appName": appName])
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try JSONDecoder().decode(CivicIntegrationConnectResult.self, from: data)
    }

    func disconnect(connectionId: String) async throws {
        let url = baseURL.appendingPathComponent("v1/integrations/\(connectionId)")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
    }

    func sendGmail(entityId: String, to: String, subject: String, body: String) async throws {
        let url = baseURL.appendingPathComponent("v1/integrations/gmail/send")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(entityId, forHTTPHeaderField: "x-athen-entity")
        request.httpBody = try JSONEncoder().encode([
            "to": to,
            "subject": subject,
            "body": body,
        ])
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
    }

    func runAutomation(entityId: String, automation: String, input: AutomationInputPayload) async throws {
        let url = baseURL.appendingPathComponent("v1/integrations/automate")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(entityId, forHTTPHeaderField: "x-athen-entity")

        struct Body: Encodable {
            let automation: String
            let input: AutomationInputPayload
        }
        request.httpBody = try JSONEncoder().encode(Body(automation: automation, input: input))
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
    }

    private func ensureSuccess(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CivicFilingError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            let msg = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
            throw CivicFilingError.server(status: http.statusCode, message: msg ?? "Integration request failed.")
        }
    }
}

struct MockIntegrationsService: IntegrationsServicing {
    func fetchCatalog() async throws -> CivicIntegrationCatalog {
        CivicIntegrationCatalog(enabled: false, apps: [])
    }
    func fetchStatus(entityId _: String) async throws -> CivicIntegrationStatusList {
        CivicIntegrationStatusList(enabled: false, items: [])
    }
    func connect(entityId _: String, appName _: String) async throws -> CivicIntegrationConnectResult {
        throw CivicFilingError.server(status: 0, message: "Connect a backend from Radar → profile → AI backend to enable integrations.")
    }
    func disconnect(connectionId _: String) async throws {
        throw CivicFilingError.server(status: 0, message: "Connect a backend from Radar → profile → AI backend to enable integrations.")
    }
    func sendGmail(entityId _: String, to _: String, subject _: String, body _: String) async throws {
        throw CivicFilingError.server(status: 0, message: "Gmail send requires backend + Composio.")
    }
    func runAutomation(entityId _: String, automation _: String, input _: AutomationInputPayload) async throws {
        throw CivicFilingError.server(status: 0, message: "Automations require a connected backend.")
    }
}

private struct ErrorEnvelope: Decodable {
    let error: Body
    struct Body: Decodable { let code: String; let message: String }
}
