import Foundation

struct ModerationReportResult: Decodable {
    let id: String
    let status: String
    let reportedAt: String
    let autoHideThresholdReached: Bool?
}

protocol ModerationServicing {
    func reportPost(postId: String, reason: String) async throws -> ModerationReportResult
}

struct HTTPModerationService: ModerationServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func reportPost(postId: String, reason: String) async throws -> ModerationReportResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/moderation/report"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "postId": postId,
            "reason": reason,
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CivicFilingError.invalidResponse
        }
        return try JSONDecoder().decode(ModerationReportResult.self, from: data)
    }
}

struct MockModerationService: ModerationServicing {
    func reportPost(postId _: String, reason _: String) async throws -> ModerationReportResult {
        ModerationReportResult(id: UUID().uuidString, status: "pending", reportedAt: ISO8601DateFormatter().string(from: .now), autoHideThresholdReached: nil)
    }
}
