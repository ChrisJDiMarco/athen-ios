import Foundation

/// Result of pasting a URL into Athen — what Claude thinks the page is about,
/// which of our tracked issues it relates to, and 2-4 things the user can do.
struct CivicUrlAnalysis: Identifiable, Decodable, Equatable {
    let url: String
    let fetchedAt: String
    let pageTitle: String?
    let summary: String
    let relatedIssues: [RelatedIssue]
    let suggestedActions: [String]
    var id: String { url + fetchedAt }

    struct RelatedIssue: Identifiable, Decodable, Equatable, Hashable {
        let id: String
        let title: String
        let scope: String
    }
}

/// Personalized impact analysis for one bill given the user's profile.
struct CivicPersonalImpact: Decodable, Equatable {
    let issueId: String
    let generatedAt: String
    let headline: String
    let details: [String]
    let confidence: Confidence
    let missingInputs: [String]

    enum Confidence: String, Decodable {
        case estimate
        case roughEstimate = "rough estimate"
        case speculative

        var label: String {
            switch self {
            case .estimate: "Estimate"
            case .roughEstimate: "Rough estimate"
            case .speculative: "Speculative"
            }
        }
    }
}

/// Persisted financial / household snapshot the user provides once, reused
/// for every "How does this affect me?" tap. Stored locally in UserDefaults.
struct CivicImpactProfile: Codable, Equatable {
    var monthlyRent: Double?
    var annualIncome: Double?
    var householdSize: Int?
    var hasKidsInPublicSchool: Bool?
    var commuteMode: CommuteMode?
    var homeOwner: Bool?

    enum CommuteMode: String, Codable, CaseIterable, Identifiable {
        case car, transit, bike, walk, remote, mixed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .car: "Car"
            case .transit: "Transit"
            case .bike: "Bike"
            case .walk: "Walk"
            case .remote: "Remote / WFH"
            case .mixed: "Mixed"
            }
        }
    }

    static let empty = CivicImpactProfile()
}
