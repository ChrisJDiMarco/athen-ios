import Foundation

protocol LifeEventsServicing {
    func plan(description: String, profile: LifeEventProfileInput?) async throws -> CivicLifeEventPlan
}

struct LifeEventProfileInput: Encodable {
    let stateCode: String?
    let stateName: String?
    let zip: String?
    let locality: String?
    let factors: [String]?
    let householdSize: Int?
    let incomeBand: String?
}

struct HTTPLifeEventsService: LifeEventsServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 120) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func plan(description: String, profile: LifeEventProfileInput?) async throws -> CivicLifeEventPlan {
        let url = baseURL.appendingPathComponent("v1/life-events/plan")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        struct Body: Encodable {
            let description: String
            let profile: LifeEventProfileInput?
        }
        request.httpBody = try JSONEncoder().encode(Body(description: description, profile: profile))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
            throw CivicFilingError.server(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: msg ?? "Plan failed.")
        }
        let payload = try JSONDecoder().decode(LifeEventPlanResponse.self, from: data)
        return CivicLifeEventPlan(
            id: UUID().uuidString,
            generatedAtISO: payload.plan.generatedAtISO,
            situation: payload.plan.situation,
            category: payload.plan.category,
            immediateSteps: payload.plan.immediateSteps,
            nearTermSteps: payload.plan.nearTermSteps,
            longerTermSteps: payload.plan.longerTermSteps,
            qualifyingPrograms: payload.plan.qualifyingPrograms,
            civicAsks: payload.plan.civicAsks,
            notes: payload.plan.notes,
            originalDescription: description
        )
    }
}

struct MockLifeEventsService: LifeEventsServicing {
    func plan(description _: String, profile _: LifeEventProfileInput?) async throws -> CivicLifeEventPlan {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to generate life-event plans.")
    }
}

private struct ErrorEnvelope: Decodable {
    let error: Body
    struct Body: Decodable { let code: String; let message: String }
}
