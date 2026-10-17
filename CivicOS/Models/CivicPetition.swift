import Foundation
import SwiftUI

/// One civic petition — a collective demand backed by verified signatures.
/// Mirrors the backend's StoredPetition shape so we can decode straight off
/// the wire. All dates are ISO-8601 in JSON; we expose `Date` accessors.
struct CivicPetition: Decodable, Equatable, Hashable, Identifiable {
    let id: String
    let title: String
    let ask: String
    let body: String
    let creatorEntityId: String
    let creatorDisplayName: String
    let attachedIssueId: String?
    let attachedIssueTitle: String?
    let targets: [PetitionTarget]
    let threshold: Int?
    let deadlineISO: String?
    let status: Status
    let createdAtISO: String
    let deliveredAtISO: String?
    let signatures: [PetitionSignature]
    let visibility: Visibility
    let deliveryTrackingId: String?
    let deliveryNote: String?

    enum Status: String, Decodable, Hashable {
        case open, delivered, expired

        var label: String {
            switch self {
            case .open: "Collecting signatures"
            case .delivered: "Delivered"
            case .expired: "Expired"
            }
        }

        var tint: Color {
            switch self {
            case .open: CivicTheme.cyan
            case .delivered: CivicTheme.green
            case .expired: CivicTheme.quietInk
            }
        }

        var systemImage: String {
            switch self {
            case .open: "person.3.sequence.fill"
            case .delivered: "checkmark.seal.fill"
            case .expired: "clock.badge.xmark.fill"
            }
        }
    }

    enum Visibility: String, Decodable, Hashable { case `public`, `private` }

    var createdAt: Date {
        ISO8601DateFormatter().date(from: createdAtISO) ?? .distantPast
    }
    var deadline: Date? {
        guard let s = deadlineISO else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }
    var deliveredAt: Date? {
        guard let s = deliveredAtISO else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }
    var signerCount: Int { signatures.count }

    /// Progress toward threshold, 0–1. Nil when there's no threshold set.
    var thresholdProgress: Double? {
        guard let threshold, threshold > 0 else { return nil }
        return min(1.0, Double(signerCount) / Double(threshold))
    }

    /// Days until deadline. Nil if no deadline. Negative when past.
    var daysUntilDeadline: Int? {
        guard let deadline else { return nil }
        return Calendar.current.dateComponents([.day], from: .now, to: deadline).day
    }
}

struct PetitionSignature: Decodable, Equatable, Hashable, Identifiable {
    let id: String
    let entityId: String
    let name: String
    let zip: String
    let comment: String?
    let signedAtISO: String

    var signedAt: Date {
        ISO8601DateFormatter().date(from: signedAtISO) ?? .distantPast
    }

    var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        let combined = (first + last).uppercased()
        return combined.isEmpty ? "?" : combined
    }
}

struct PetitionTarget: Decodable, Equatable, Hashable {
    let officialName: String
    let jurisdiction: String
    let email: String?
    let contactFormURL: String?
    let channel: Channel

    enum Channel: String, Decodable, Hashable {
        case email
        case contactFormQueue = "contact-form-queue"
    }
}

struct CivicPetitionListResponse: Decodable, Equatable, Hashable {
    let items: [CivicPetition]
    let stats: Stats
    let viewer: ViewerSummary?

    struct Stats: Decodable, Equatable, Hashable {
        let total: Int
        let open: Int
        let delivered: Int
        let expired: Int
        let totalSignatures: Int
    }

    struct ViewerSummary: Decodable, Equatable, Hashable {
        let signedIds: [String]
        let createdIds: [String]
    }
}

struct CivicPetitionDetailResponse: Decodable, Equatable, Hashable {
    let petition: CivicPetition
    let viewer: ViewerState?

    struct ViewerState: Decodable, Equatable, Hashable {
        let hasSigned: Bool
        let isCreator: Bool
    }
}

struct CivicPetitionDeliveryResult: Decodable, Equatable, Hashable {
    let trackingId: String
    let channel: String
    let deliveredTo: String
    let note: String
}
