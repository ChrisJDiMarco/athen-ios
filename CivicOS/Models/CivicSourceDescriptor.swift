import Foundation
import SwiftUI

/// One configured upstream civic data source as reported by `/v1/sources`.
/// Read-only from the device side — the backend owns the canonical registry.
/// The device can locally hide a source from its UI (see
/// `AppSettings.disabledSourceIDs`), but cannot mutate the registry itself.
struct CivicSourceDescriptor: Identifiable, Equatable, Hashable, Decodable {
    enum Scope: String, Codable, CaseIterable {
        case federal, state
        case localPhilly = "local-philly"
        case unknown

        var label: String {
            switch self {
            case .federal: return "Federal"
            case .state: return "State"
            case .localPhilly: return "Local — Philly"
            case .unknown: return "Other"
            }
        }

        var tint: Color {
            switch self {
            case .federal: return CivicTheme.cyan
            case .state: return CivicTheme.violet
            case .localPhilly: return CivicTheme.amber
            case .unknown: return CivicTheme.quietInk
            }
        }
    }

    enum Kind: String, Codable {
        case legistar
        case officialWeb = "official-web"
        case officialApi = "official-api"
        case verifiedWeb = "verified-web"

        var label: String {
            switch self {
            case .legistar: return "Legistar"
            case .officialWeb: return "Official web"
            case .officialApi: return "Official API"
            case .verifiedWeb: return "Verified web"
            }
        }

        var systemImage: String {
            switch self {
            case .legistar: return "doc.text.fill"
            case .officialWeb: return "building.columns.fill"
            case .officialApi: return "antenna.radiowaves.left.and.right"
            case .verifiedWeb: return "checkmark.shield.fill"
            }
        }
    }

    enum TrustTier: String, Codable {
        case official, verified, watch

        var label: String {
            switch self {
            case .official: return "Official"
            case .verified: return "Verified"
            case .watch: return "Watch"
            }
        }

        var tint: Color {
            switch self {
            case .official: return CivicTheme.green
            case .verified: return CivicTheme.cyan
            case .watch: return CivicTheme.amber
            }
        }
    }

    let id: String
    let name: String
    let jurisdiction: String
    let scope: Scope
    let stateCode: String?
    let kind: Kind
    let trustTier: TrustTier
    let url: String
    let primaryHost: String
    let allowedHosts: [String]
    let defaultContactTarget: String
    let issueCount: Int
    let lastUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, jurisdiction, scope, stateCode, kind, trustTier
        case url, primaryHost, allowedHosts, defaultContactTarget
        case issueCount, lastUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        jurisdiction = try c.decode(String.self, forKey: .jurisdiction)
        scope = (try? c.decode(Scope.self, forKey: .scope)) ?? .unknown
        stateCode = try c.decodeIfPresent(String.self, forKey: .stateCode)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .officialWeb
        trustTier = (try? c.decode(TrustTier.self, forKey: .trustTier)) ?? .verified
        url = try c.decode(String.self, forKey: .url)
        primaryHost = try c.decode(String.self, forKey: .primaryHost)
        allowedHosts = (try? c.decode([String].self, forKey: .allowedHosts)) ?? []
        defaultContactTarget = try c.decode(String.self, forKey: .defaultContactTarget)
        issueCount = (try? c.decode(Int.self, forKey: .issueCount)) ?? 0
        if let raw = try c.decodeIfPresent(String.self, forKey: .lastUpdatedAt) {
            lastUpdatedAt = ISO8601DateFormatter().date(from: raw)
        } else {
            lastUpdatedAt = nil
        }
    }
}

struct CivicSourcesSnapshot: Equatable {
    let generatedAt: Date
    let sources: [CivicSourceDescriptor]
    let registered: Int
    let activeHosts: Int
    let totalIssues: Int
}

/// Refresh cadence the user can pick for automatic background pulls of
/// /v1/issues. `manualOnly` means "don't poll — only refresh when the user
/// taps the Home refresh button or pulls to refresh".
enum RefreshInterval: Int, CaseIterable, Codable, Identifiable {
    case manualOnly = 0
    case every15 = 15
    case every30 = 30
    case hourly = 60
    case every4Hours = 240
    case daily = 1440

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .manualOnly: return "Manual only"
        case .every15: return "Every 15 min"
        case .every30: return "Every 30 min"
        case .hourly: return "Every hour"
        case .every4Hours: return "Every 4 hours"
        case .daily: return "Once a day"
        }
    }

    var shortLabel: String {
        switch self {
        case .manualOnly: return "Manual"
        case .every15: return "15m"
        case .every30: return "30m"
        case .hourly: return "1h"
        case .every4Hours: return "4h"
        case .daily: return "Daily"
        }
    }
}
