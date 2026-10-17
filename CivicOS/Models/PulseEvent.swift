import Foundation
import SwiftUI

/// Unified event type for the Pulse activity stream. Replaces the
/// previous five-card layout with one chronological feed that mixes
/// bills, votes, social posts, petitions, diffs, and momentum signals.
///
/// All variants are local-derivable from store state — no new backend
/// needed for v1. Live SSE push hooks in v1.1.
struct PulseEvent: Identifiable, Hashable {
    let id: String
    let kind: Kind
    let timestamp: Date
    let title: String
    let subtitle: String
    let issueID: UUID?
    /// Used for ranking — higher floats up. Combines recency + importance.
    let weight: Double

    enum Kind: Hashable {
        case billIntroduced
        case voteScheduled
        case voteImminent      // < 48h
        case positionMomentum  // X people endorsed/opposed lately
        case petitionMilestone // hit 10/50/100/500/1000 signers
        case squarePost
        case briefReady        // new AI brief generated
        case diffChange        // bill status changed
    }

    var icon: String {
        switch kind {
        case .billIntroduced: return "doc.text.fill"
        case .voteScheduled: return "calendar"
        case .voteImminent: return "exclamationmark.triangle.fill"
        case .positionMomentum: return "person.3.fill"
        case .petitionMilestone: return "flag.checkered"
        case .squarePost: return "bubble.left.and.bubble.right.fill"
        case .briefReady: return "sparkles"
        case .diffChange: return "arrow.triangle.2.circlepath"
        }
    }

    var tint: Color {
        switch kind {
        case .billIntroduced: return CivicTheme.cyan
        case .voteScheduled: return CivicTheme.violet
        case .voteImminent: return CivicTheme.red
        case .positionMomentum: return CivicTheme.green
        case .petitionMilestone: return CivicTheme.green
        case .squarePost: return CivicTheme.cyan
        case .briefReady: return CivicTheme.violet
        case .diffChange: return CivicTheme.amber
        }
    }

    var categoryLabel: String {
        switch kind {
        case .billIntroduced: return "NEW BILL"
        case .voteScheduled: return "VOTE SCHEDULED"
        case .voteImminent: return "VOTE SOON"
        case .positionMomentum: return "MOMENTUM"
        case .petitionMilestone: return "PETITION"
        case .squarePost: return "FROM SQUARE"
        case .briefReady: return "NEW BRIEF"
        case .diffChange: return "CHANGE"
        }
    }
}

/// Scope filter chips at the top of the Pulse feed.
enum PulseScope: String, CaseIterable, Identifiable {
    case all, mine, federal, state, local

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .mine: return "My ZIP"
        case .federal: return "Federal"
        case .state: return "State"
        case .local: return "Local"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "globe"
        case .mine: return "location.fill"
        case .federal: return "building.columns.fill"
        case .state: return "map.fill"
        case .local: return "house.fill"
        }
    }
}
