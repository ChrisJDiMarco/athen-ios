import Foundation
import SwiftUI

/// All voter-rail models. Mirror the backend's voter response shapes so
/// they decode straight off the wire. Election dates come back as "YYYY-MM-DD"
/// strings from Google Civic — we expose `electionDate` as a `Date`.

struct CivicElection: Decodable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String
    let electionDay: String
    let ocdDivisionId: String?

    var electionDate: Date? {
        let formatter = DateFormatter()
        formatter.calendar = .init(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = .init(identifier: "en_US_POSIX")
        return formatter.date(from: electionDay)
    }

    var daysUntil: Int? {
        guard let date = electionDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day
    }

    var isToday: Bool { daysUntil == 0 }
    var isPast: Bool { (daysUntil ?? 1) < 0 }
}

struct CivicElectionsResponse: Decodable, Equatable {
    let enabled: Bool
    let elections: [CivicElection]
    let notice: String?
}

struct PollingPlace: Decodable, Equatable, Hashable, Identifiable {
    let name: String
    let address: String
    let pollingHours: String?
    let notes: String?
    let latitude: Double?
    let longitude: Double?
    let sources: [Source]?

    var id: String { name + "|" + address }

    struct Source: Decodable, Equatable, Hashable {
        let name: String
        let official: Bool
    }
}

struct CivicPollingPlaceResponse: Decodable, Equatable {
    let enabled: Bool
    let pollingPlaces: [PollingPlace]
    let earlyVoteSites: [PollingPlace]?
    let dropOffLocations: [PollingPlace]?
    let election: CivicElection?
    let state: StateInfo?
    let notice: String?

    struct StateInfo: Decodable, Equatable, Hashable {
        let name: String?
        let electionAdministrationBody: ElectionBody?

        struct ElectionBody: Decodable, Equatable, Hashable {
            let name: String?
            let electionInfoUrl: String?
            let ballotInfoUrl: String?
        }
    }
}

// MARK: - Sample ballot

struct SampleBallot: Decodable, Equatable, Hashable {
    let generatedAtISO: String
    let electionId: String?
    let electionName: String?
    let electionDay: String?
    let contests: [BallotContest]
    let notice: String
}

struct BallotContest: Decodable, Equatable, Hashable, Identifiable {
    let fingerprint: String
    let kind: Kind
    let title: String
    let office: String?
    let district: String?
    let plainEnglish: String
    let whatYesMeans: String?
    let whatNoMeans: String?
    let considerations: [String]
    let candidates: [BallotBriefCandidate]?
    let rawText: String?

    var id: String { fingerprint }

    enum Kind: String, Decodable, Hashable {
        case candidate, measure, judicial, other

        var label: String {
            switch self {
            case .candidate: "Race"
            case .measure: "Measure"
            case .judicial: "Judicial"
            case .other: "Item"
            }
        }

        var systemImage: String {
            switch self {
            case .candidate: "person.text.rectangle.fill"
            case .measure: "checklist"
            case .judicial: "scale.3d"
            case .other: "questionmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .candidate: CivicTheme.cyan
            case .measure: CivicTheme.violet
            case .judicial: CivicTheme.amber
            case .other: CivicTheme.mutedInk
            }
        }
    }
}

struct BallotBriefCandidate: Decodable, Equatable, Hashable, Identifiable {
    let name: String
    let party: String?
    let blurb: String?

    var id: String { name }
}

struct CivicBallotResponse: Decodable, Equatable {
    let enabled: Bool
    let ballot: SampleBallot?
    let pollingPlaces: [PollingPlace]?
    let state: CivicPollingPlaceResponse.StateInfo?
    let notice: String?
}

// MARK: - State registration

struct StateRegistrationInfo: Decodable, Equatable, Hashable, Identifiable {
    let stateCode: String
    let stateName: String
    let portalURL: String
    let online: Bool
    let sameDay: Bool
    let automaticAtDMV: Bool
    let deadlineDaysBeforeElection: Int
    let idRequirements: String
    let notes: String?

    var id: String { stateCode }

    var deadlineLabel: String {
        switch deadlineDaysBeforeElection {
        case ..<0: return "Same day allowed"
        case 0: return sameDay ? "Same day allowed" : "Check portal"
        default: return "\(deadlineDaysBeforeElection) days before election"
        }
    }
}

struct CivicRegistrationResponse: Decodable, Equatable {
    let registration: StateRegistrationInfo
}

// MARK: - Rep scorecard

struct RepScorecardResponse: Decodable, Equatable {
    let scorecards: [RepScorecard]
    let notFiledYet: [String]
    let generatedAtISO: String
}

struct RepScorecard: Decodable, Equatable, Hashable, Identifiable {
    let officialName: String
    let totalFilings: Int
    let endorseCount: Int
    let opposeCount: Int
    let topicBreakdown: [TopicCount]
    let mismatches: [ScorecardMismatch]
    let pending: [ScorecardMismatch]
    let alignmentPct: Int?
    let history: [ScorecardHistoryEntry]

    var id: String { officialName }

    struct TopicCount: Decodable, Equatable, Hashable, Identifiable {
        let topic: String
        let count: Int
        var id: String { topic }
    }
}

struct ScorecardMismatch: Decodable, Equatable, Hashable, Identifiable {
    let issueId: String
    let issueTitle: String
    let userPosition: String
    let officialVote: String?
    let voteDateISO: String?

    var id: String { issueId + (officialVote ?? "") }
}

struct ScorecardHistoryEntry: Decodable, Equatable, Hashable, Identifiable {
    let issueId: String
    let issueTitle: String
    let position: String
    let filedAtISO: String
    let vote: String?
    let voteDateISO: String?

    var id: String { issueId + filedAtISO }
}
