import Foundation

// MARK: - Paste-any-URL analyzer

protocol UrlAnalyzeServicing {
    func analyze(url: String) async throws -> CivicUrlAnalysis
}

struct HTTPUrlAnalyzeService: UrlAnalyzeServicing {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = AthenURLSession.shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func analyze(url: String) async throws -> CivicUrlAnalysis {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/url/analyze"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(["url": url])
        // Firecrawl + Claude can take 15-25s combined; give it room.
        req.timeoutInterval = 60
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CivicFilingError.server(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: body.isEmpty ? "URL analysis failed." : String(body.prefix(180)))
        }
        return try JSONDecoder().decode(CivicUrlAnalysis.self, from: data)
    }
}

struct MockUrlAnalyzeService: UrlAnalyzeServicing {
    func analyze(url _: String) async throws -> CivicUrlAnalysis {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to analyze URLs.")
    }
}

// MARK: - Personal impact calculator

protocol PersonalImpactServicing {
    func estimate(issueId: String, profile: CivicImpactProfile, zip: String?, state: String?) async throws -> CivicPersonalImpact
}

struct HTTPPersonalImpactService: PersonalImpactServicing {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = AthenURLSession.shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func estimate(issueId: String, profile: CivicImpactProfile, zip: String?, state: String?) async throws -> CivicPersonalImpact {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/issues/\(issueId)/impact"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 45

        struct Body: Encodable {
            let monthlyRent: Double?
            let annualIncome: Double?
            let householdSize: Int?
            let hasKidsInPublicSchool: Bool?
            let commuteMode: String?
            let homeOwner: Bool?
            let zip: String?
            let state: String?
        }
        let body = Body(
            monthlyRent: profile.monthlyRent,
            annualIncome: profile.annualIncome,
            householdSize: profile.householdSize,
            hasKidsInPublicSchool: profile.hasKidsInPublicSchool,
            commuteMode: profile.commuteMode?.rawValue,
            homeOwner: profile.homeOwner,
            zip: zip,
            state: state,
        )
        let encoder = JSONEncoder()
        req.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw CivicFilingError.server(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: bodyStr.isEmpty ? "Impact request failed." : String(bodyStr.prefix(180)))
        }
        return try JSONDecoder().decode(CivicPersonalImpact.self, from: data)
    }
}

struct MockPersonalImpactService: PersonalImpactServicing {
    func estimate(issueId _: String, profile _: CivicImpactProfile, zip _: String?, state _: String?) async throws -> CivicPersonalImpact {
        throw CivicFilingError.server(status: 0, message: "Connect a backend to estimate personal impact.")
    }
}
