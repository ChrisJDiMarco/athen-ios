import Foundation

struct SpeechSynthesisResult: Equatable, Decodable {
    enum Payload: Equatable {
        case elevenlabs(base64: String, contentType: String, bytes: Int, voiceId: String, modelId: String)
        case clientFallback(reason: String)
    }

    let payload: Payload

    private enum Keys: String, CodingKey {
        case provider, base64, contentType, bytes, reason, voiceId, modelId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let provider = try c.decode(String.self, forKey: .provider)
        switch provider {
        case "elevenlabs":
            payload = .elevenlabs(
                base64: try c.decode(String.self, forKey: .base64),
                contentType: try c.decode(String.self, forKey: .contentType),
                bytes: try c.decode(Int.self, forKey: .bytes),
                voiceId: try c.decode(String.self, forKey: .voiceId),
                modelId: try c.decode(String.self, forKey: .modelId)
            )
        default:
            payload = .clientFallback(reason: (try? c.decode(String.self, forKey: .reason)) ?? "")
        }
    }
}

struct SpeechVoice: Equatable, Hashable, Decodable, Identifiable {
    let id: String
    let name: String
    let category: String
    let description: String?
    let previewUrl: String?
}

struct SpeechVoicesResponse: Decodable {
    let voices: [SpeechVoice]
}

protocol SpeechServicing {
    func synthesize(text: String, voiceId: String?, modelId: String?) async throws -> SpeechSynthesisResult
    func listVoices() async throws -> [SpeechVoice]
}

struct HTTPSpeechService: SpeechServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 60) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func synthesize(text: String, voiceId: String?, modelId: String?) async throws -> SpeechSynthesisResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/speech/synthesize"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var body: [String: Any] = ["text": text]
        if let voiceId, !voiceId.isEmpty { body["voiceId"] = voiceId }
        if let modelId, !modelId.isEmpty { body["modelId"] = modelId }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CivicFilingError.invalidResponse
        }
        return try JSONDecoder().decode(SpeechSynthesisResult.self, from: data)
    }

    func listVoices() async throws -> [SpeechVoice] {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/speech/voices"), timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CivicFilingError.invalidResponse
        }
        return try JSONDecoder().decode(SpeechVoicesResponse.self, from: data).voices
    }
}

struct MockSpeechService: SpeechServicing {
    func synthesize(text _: String, voiceId _: String?, modelId _: String?) async throws -> SpeechSynthesisResult {
        let json = #"{"provider":"client-fallback","reason":"Connect CIVIC_API_BASE_URL to enable Athen voice."}"#
        return try JSONDecoder().decode(SpeechSynthesisResult.self, from: Data(json.utf8))
    }

    func listVoices() async throws -> [SpeechVoice] { [] }
}
