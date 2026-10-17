import Foundation
import SwiftUI

/// One elected official surfaced in the master directory. Mirrors the
/// backend's DirectoryOfficial shape. Decodable straight off the wire.
struct DirectoryOfficial: Decodable, Equatable, Hashable, Identifiable {
    let id: String
    let level: Level
    let name: String
    let photoURL: String?
    let role: String
    let party: String?
    let jurisdiction: String
    let state: String?
    let district: String?
    let chamber: Chamber?
    let termStartISO: String?
    let termEndISO: String?
    let bioBirthday: String?
    let gender: String?
    let websites: [String]
    let offices: [Office]
    let socials: Socials
    let externalIDs: ExternalIDs
    let bio: String?
    let fetchedAtISO: String

    enum Level: String, Decodable, Hashable {
        case federal, state, local

        var label: String {
            switch self {
            case .federal: "Federal"
            case .state: "State"
            case .local: "Local"
            }
        }

        var tint: Color {
            switch self {
            case .federal: CivicTheme.cyan
            case .state: CivicTheme.violet
            case .local: CivicTheme.amber
            }
        }
    }

    enum Chamber: String, Decodable, Hashable {
        case senate, house, executive, judicial, other

        var label: String {
            switch self {
            case .senate: "Senate"
            case .house: "House"
            case .executive: "Executive"
            case .judicial: "Judicial"
            case .other: "Other"
            }
        }
    }

    struct Office: Decodable, Equatable, Hashable, Identifiable {
        let type: String
        let label: String
        let address: String?
        let phone: String?
        let fax: String?

        var id: String { label + (address ?? "") }
    }

    struct Socials: Decodable, Equatable, Hashable {
        let twitter: String?
        let facebook: String?
        let instagram: String?
        let youtube: String?
        let linkedin: String?
        let tiktok: String?

        var any: Bool {
            twitter != nil || facebook != nil || instagram != nil
                || youtube != nil || linkedin != nil || tiktok != nil
        }
    }

    struct ExternalIDs: Decodable, Equatable, Hashable {
        let bioguide: String?
        let govtrack: Int?
        let opensecrets: String?
        let fec: [String]?
        let votesmart: Int?
        let wikipedia: String?
        let ballotpedia: String?
        let wikidata: String?
        let openstates: String?
    }

    var partyTint: Color {
        guard let p = party?.lowercased() else { return CivicTheme.quietInk }
        if p.contains("democrat") { return Color(red: 0.10, green: 0.40, blue: 0.85) }
        if p.contains("republican") { return Color(red: 0.85, green: 0.20, blue: 0.20) }
        if p.contains("independent") { return CivicTheme.violet }
        if p.contains("green") { return CivicTheme.green }
        if p.contains("libertarian") { return CivicTheme.amber }
        return CivicTheme.quietInk
    }

    var partyAbbreviation: String {
        guard let p = party else { return "" }
        if p.lowercased().contains("democrat") { return "D" }
        if p.lowercased().contains("republican") { return "R" }
        if p.lowercased().contains("independent") { return "I" }
        return String(p.prefix(1)).uppercased()
    }

    var wikipediaURL: URL? {
        guard let slug = externalIDs.wikipedia, !slug.isEmpty else { return nil }
        return URL(string: "https://en.wikipedia.org/wiki/\(slug.replacingOccurrences(of: " ", with: "_"))")
    }

    var ballotpediaURL: URL? {
        guard let slug = externalIDs.ballotpedia, !slug.isEmpty else { return nil }
        return URL(string: "https://ballotpedia.org/\(slug.replacingOccurrences(of: " ", with: "_"))")
    }

    var openSecretsURL: URL? {
        guard let cid = externalIDs.opensecrets, !cid.isEmpty else { return nil }
        return URL(string: "https://www.opensecrets.org/members-of-congress/summary?cid=\(cid)")
    }

    var displayDistrict: String {
        if let district { return district }
        if let state { return state }
        return jurisdiction
    }
}

struct DirectoryOfficialsResponse: Decodable, Equatable {
    let officials: [DirectoryOfficial]
}

struct DirectoryOfficialDetailResponse: Decodable, Equatable {
    let official: DirectoryOfficial
}
