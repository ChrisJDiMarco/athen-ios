import Foundation

protocol ProfileResolverServicing {
    func resolve(zip: String) async throws -> UserProfile
}

struct HTTPProfileResolverService: ProfileResolverServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 15) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func resolve(zip: String) async throws -> UserProfile {
        let url = baseURL.appendingPathComponent("v1/profile/resolve")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["zip": zip])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CivicFilingError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            let message = (try? JSONDecoder().decode(ProfileErrorResponse.self, from: data))?.error.message
            throw CivicFilingError.server(status: http.statusCode, message: message ?? "Could not resolve ZIP.")
        }

        let decoded = try JSONDecoder().decode(ProfileResolveResponse.self, from: data)
        return decoded.toUserProfile()
    }
}

struct MockProfileResolverService: ProfileResolverServicing {
    func resolve(zip: String) async throws -> UserProfile {
        try await Task.sleep(nanoseconds: 250_000_000)
        let stateCode: String
        let stateName: String
        switch zip.prefix(3) {
        case "191": stateCode = "PA"; stateName = "Pennsylvania"
        case "100", "101", "102", "103", "104": stateCode = "NY"; stateName = "New York"
        case "900", "902", "903": stateCode = "CA"; stateName = "California"
        default: stateCode = "US"; stateName = "United States"
        }

        let officials = ResolvedOfficials(
            federalSenators: [
                OfficialSummary(name: "Senior U.S. Senator for \(stateName)", title: "United States Senator", level: "federal-senate", district: "State of \(stateName)", party: nil, contactLabel: "senate.gov"),
                OfficialSummary(name: "Junior U.S. Senator for \(stateName)", title: "United States Senator", level: "federal-senate", district: "State of \(stateName)", party: nil, contactLabel: "senate.gov")
            ],
            federalHouseRep: OfficialSummary(name: "U.S. Representative for \(stateName)", title: "Member, U.S. House of Representatives", level: "federal-house", district: "\(stateCode)-AL", party: nil, contactLabel: "house.gov"),
            stateSenators: [],
            stateRepresentatives: [],
            local: zip.hasPrefix("191")
                ? [OfficialSummary(name: "Councilmember District 4", title: "District Councilmember", level: "local", district: "District 4", party: nil, contactLabel: "phila.gov")]
                : []
        )

        return UserProfile(
            zipCode: String(zip.prefix(5)),
            stateCode: stateCode,
            stateName: stateName,
            congressionalDistrict: nil,
            localityLabel: zip.hasPrefix("191") ? "Philadelphia" : nil,
            officials: officials
        )
    }
}

private struct ProfileResolveResponse: Decodable {
    let location: Location
    let officials: Officials

    struct Location: Decodable {
        let zipCode: String
        let stateCode: String
        let stateName: String
        let city: String?
        let normalized: String?
        let source: String
    }

    struct Officials: Decodable {
        let federalSenators: [OfficialJSON]
        let federalHouseRep: OfficialJSON?
        let stateSenators: [OfficialJSON]
        let stateRepresentatives: [OfficialJSON]
        let local: [OfficialJSON]
    }

    struct OfficialJSON: Decodable {
        let name: String
        let title: String
        let level: String
        let district: String?
        let contactLabel: String?
    }

    func toUserProfile() -> UserProfile {
        let mapped = ResolvedOfficials(
            federalSenators: officials.federalSenators.map(\.toSummary),
            federalHouseRep: officials.federalHouseRep?.toSummary,
            stateSenators: officials.stateSenators.map(\.toSummary),
            stateRepresentatives: officials.stateRepresentatives.map(\.toSummary),
            local: officials.local.map(\.toSummary)
        )
        return UserProfile(
            zipCode: location.zipCode,
            stateCode: location.stateCode,
            stateName: location.stateName,
            congressionalDistrict: nil,
            localityLabel: location.city,
            officials: mapped
        )
    }
}

private extension ProfileResolveResponse.OfficialJSON {
    var toSummary: OfficialSummary {
        OfficialSummary(name: name, title: title, level: level, district: district, party: nil, contactLabel: contactLabel)
    }
}

private struct ProfileErrorResponse: Decodable {
    let error: ErrorBody
    struct ErrorBody: Decodable { let code: String; let message: String }
}
