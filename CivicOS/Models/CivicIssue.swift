import Foundation

struct CivicIssue: Identifiable, Hashable {
    let id: UUID
    let title: String
    let category: String
    let jurisdiction: String
    let scope: JurisdictionScope
    let zipCode: String
    let summary: String
    let impactLevel: ImpactLevel
    let voteDate: Date
    let sourceName: String
    let sourceDetail: String
    let sourceURL: String?
    let facts: [TranslationFact]
    let official: LocalOfficial
    let filingRoute: FilingRoute
    let reply: OfficialReply?
    let topics: Set<CivicTopic>
    let trustScoreOverride: Int?
    let extractionConfidence: Double?
    let sourceHost: String?
    let sourceType: String?
    let citations: [IssueCitation]

    init(
        id: UUID,
        title: String,
        category: String,
        jurisdiction: String,
        scope: JurisdictionScope,
        zipCode: String,
        summary: String,
        impactLevel: ImpactLevel,
        voteDate: Date,
        sourceName: String,
        sourceDetail: String,
        sourceURL: String?,
        facts: [TranslationFact],
        official: LocalOfficial,
        filingRoute: FilingRoute,
        reply: OfficialReply?,
        topics: Set<CivicTopic>,
        trustScoreOverride: Int? = nil,
        extractionConfidence: Double? = nil,
        sourceHost: String? = nil,
        sourceType: String? = nil,
        citations: [IssueCitation] = []
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.jurisdiction = jurisdiction
        self.scope = scope
        self.zipCode = zipCode
        self.summary = summary
        self.impactLevel = impactLevel
        self.voteDate = voteDate
        self.sourceName = sourceName
        self.sourceDetail = sourceDetail
        self.sourceURL = sourceURL
        self.facts = facts
        self.official = official
        self.filingRoute = filingRoute
        self.reply = reply
        self.topics = topics
        self.trustScoreOverride = trustScoreOverride
        self.extractionConfidence = extractionConfidence
        self.sourceHost = sourceHost
        self.sourceType = sourceType
        self.citations = citations
    }
}

extension CivicIssue {
    /// Concise countdown label like "2h", "4d", "Today", "Past".
    var voteCountdownLabel: String {
        let now = Date.now
        let interval = voteDate.timeIntervalSince(now)
        if interval < -60 * 60 { return "Past" }
        if interval < 60 * 60 {
            let mins = max(0, Int(interval / 60))
            return mins == 0 ? "Now" : "\(mins)m"
        }
        if interval < 24 * 60 * 60 {
            let hours = Int(interval / 3600)
            return hours == 0 ? "<1h" : "\(hours)h"
        }
        let days = Int(interval / 86400)
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return "\(days)d"
        case 7...13: return "1wk"
        default: return "\(days / 7)wk"
        }
    }

    /// Hours until the vote. Negative = already happened.
    var hoursUntilVote: Double {
        voteDate.timeIntervalSince(.now) / 3600
    }

    /// Coarse urgency tier driven by clock + impact level.
    var urgencyTint: ImpactLevel {
        if hoursUntilVote < 48 { return .urgent }
        if hoursUntilVote < 168 { return .material }
        return impactLevel
    }
}

enum JurisdictionScope: Hashable {
    case federal
    case state(String)
    case localPhilly

    /// True when this scope refers to a federal regulatory agency rather
    /// than Congress. Those items can't be filed via email — they require
    /// a public comment on the source (e.g. regulations.gov / Federal
    /// Register). Used to swap Endorse/Oppose for a "Comment on source"
    /// CTA in the action bar.
    static func isRegulatory(jurisdiction: String, scope: JurisdictionScope) -> Bool {
        guard case .federal = scope else { return false }
        let normalized = jurisdiction.trimmingCharacters(in: .whitespacesAndNewlines)
        // Anything in Congress is filable; everything else federal is
        // assumed to be regulatory (Department, Agency, Service, etc.).
        if normalized == "U.S. House of Representatives" { return false }
        if normalized == "U.S. Senate" { return false }
        if normalized == "Congress" || normalized == "U.S. Congress" { return false }
        return true
    }

    func matches(profile: UserProfile?) -> Bool {
        switch self {
        case .federal:
            return true
        case let .state(code):
            return profile?.stateCode.caseInsensitiveCompare(code) == .orderedSame
        case .localPhilly:
            return profile?.zipCode.hasPrefix("191") == true
        }
    }

    var shortLabel: String {
        switch self {
        case .federal: "Federal"
        case let .state(code): "State (\(code.uppercased()))"
        case .localPhilly: "Local — Philadelphia"
        }
    }
}

enum ImpactLevel: String, Hashable {
    case urgent = "High Impact"
    case material = "Material"
    case watch = "Watch"

    var symbolName: String {
        switch self {
        case .urgent:
            "exclamationmark.triangle.fill"
        case .material:
            "building.columns.fill"
        case .watch:
            "eye.fill"
        }
    }
}

struct TranslationFact: Identifiable, Hashable {
    let id: UUID
    let label: String
    let value: String
    let systemImage: String

    init(id: UUID = UUID(), label: String, value: String, systemImage: String) {
        self.id = id
        self.label = label
        self.value = value
        self.systemImage = systemImage
    }
}

struct IssueCitation: Identifiable, Hashable {
    let id: UUID
    let label: String
    let quote: String
    let url: String?

    init(id: UUID = UUID(), label: String, quote: String, url: String? = nil) {
        self.id = id
        self.label = label
        self.quote = quote
        self.url = url
    }
}

struct LocalOfficial: Identifiable, Hashable {
    let id: UUID
    let name: String
    let title: String
    let district: String
    let contactTarget: String
}

struct FilingRoute: Hashable {
    let verificationStep: String
    let routingStep: String
    let destinationStep: String
    let deliveryWindow: String
}

struct OfficialReply: Identifiable, Hashable {
    let id: UUID
    let receivedAt: Date
    let summary: String
    let stance: String
}
