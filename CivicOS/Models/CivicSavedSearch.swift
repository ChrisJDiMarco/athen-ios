import Foundation

/// Persisted saved search returned by the backend. Reporters, Hill staff,
/// and engaged citizens all use the same model — what varies is what
/// they query for ("rural broadband", "Rep. Smith", their state).
struct CivicSavedSearch: Identifiable, Hashable, Codable {
    let id: String
    let installId: String
    var name: String
    var query: String
    var scope: Scope
    var stateCode: String?
    var alertsEnabled: Bool
    let createdAt: String
    var updatedAt: String
    var matchedIssueIds: [String]
    var lastSeenAt: String?
    /// Server-computed count of issues that currently match this search.
    /// Populated by GET /v1/saved-searches list view.
    var currentMatchCount: Int?

    enum Scope: String, Codable, CaseIterable, Identifiable {
        case any
        case federal
        case state
        case localPhilly = "local-philly"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any: "Anywhere"
            case .federal: "Federal"
            case .state: "State"
            case .localPhilly: "Philadelphia"
            }
        }
    }

    /// Count of matches that have appeared since the user last viewed the
    /// search list (i.e., "fresh" hits). Used for the unread badge.
    var freshMatchCount: Int {
        // Without per-match timestamps, approximate: the difference between
        // currentMatchCount and the matchedIssueIds we've already recorded.
        guard let current = currentMatchCount else { return 0 }
        return max(0, current - matchedIssueIds.count)
    }
}

struct CivicSavedSearchListResponse: Codable {
    let items: [CivicSavedSearch]
}

struct CivicSavedSearchCreateResponse: Codable {
    let search: CivicSavedSearch
    let initialMatchCount: Int
}

struct CivicSavedSearchSingleResponse: Codable {
    let search: CivicSavedSearch
}
