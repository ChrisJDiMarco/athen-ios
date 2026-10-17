import Foundation

protocol BallotServicing {
    func analyze(text: String) async throws -> BallotAnalysis
}

struct HTTPBallotService: BallotServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 90) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func analyze(text: String) async throws -> BallotAnalysis {
        let url = baseURL.appendingPathComponent("v1/ballot/analyze")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["text": text])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
            throw CivicFilingError.server(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: msg ?? "Ballot analysis failed.")
        }
        return try JSONDecoder().decode(BallotAnalysis.self, from: data)
    }
}

struct MockBallotService: BallotServicing {
    func analyze(text _: String) async throws -> BallotAnalysis {
        throw CivicFilingError.server(status: 0, message: "Connect a backend from Radar → profile → AI backend to analyze ballots.")
    }
}

private struct ErrorResponse: Decodable {
    let error: Body
    struct Body: Decodable { let code: String; let message: String }
}
