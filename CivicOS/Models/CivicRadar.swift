import Foundation
import SwiftUI

enum CivicRadarPriority: Int, Hashable {
    case actNow = 4
    case priority = 3
    case watch = 2
    case followUp = 1

    var label: String {
        switch self {
        case .actNow: "Act now"
        case .priority: "Priority"
        case .watch: "Watch"
        case .followUp: "Follow up"
        }
    }

    var systemImage: String {
        switch self {
        case .actNow: "bolt.fill"
        case .priority: "target"
        case .watch: "eye.fill"
        case .followUp: "arrow.triangle.2.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .actNow: CivicTheme.amber
        case .priority: CivicTheme.cyan
        case .watch: CivicTheme.violet
        case .followUp: CivicTheme.green
        }
    }
}

struct CivicRadarInsight: Identifiable, Hashable {
    var id: CivicIssue.ID { issue.id }

    let issue: CivicIssue
    let priority: CivicRadarPriority
    let score: Int
    let reason: String
    let recommendedAction: String
    let timing: String
}

enum CivicRadarLens: String, CaseIterable, Identifiable, Hashable {
    case personal
    case actNow
    case power
    case social
    case learn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .personal: "Affects me"
        case .actNow: "Act now"
        case .power: "Power"
        case .social: "People"
        case .learn: "Learn"
        }
    }

    var systemImage: String {
        switch self {
        case .personal: "person.crop.circle.badge.checkmark"
        case .actNow: "bolt.fill"
        case .power: "building.columns.fill"
        case .social: "person.2.wave.2.fill"
        case .learn: "text.magnifyingglass"
        }
    }

    var tint: Color {
        switch self {
        case .personal: CivicTheme.violet
        case .actNow: CivicTheme.amber
        case .power: CivicTheme.cyan
        case .social: CivicTheme.green
        case .learn: CivicTheme.mutedInk
        }
    }
}

struct CivicPowerMap: Hashable {
    let decisionMaker: String
    let venue: String
    let publicChannel: String
    let sourceSignal: String
    let pressurePoint: String
}

extension CivicOSStore {
    var radarInsights: [CivicRadarInsight] {
        visibleIssues
            .map { issue in radarInsight(for: issue) }
            .sorted { lhs, rhs in
                if lhs.priority.rawValue != rhs.priority.rawValue {
                    return lhs.priority.rawValue > rhs.priority.rawValue
                }
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.issue.voteDate < rhs.issue.voteDate
            }
    }

    var topRadarInsight: CivicRadarInsight? {
        radarInsights.first
    }

    var dueSoonCount: Int {
        visibleIssues.filter { !$0.hasVotePassed && $0.hoursUntilVote <= 72 }.count
    }

    var readyToActCount: Int {
        visibleIssues.filter { !status(for: $0).isSent && !$0.hasVotePassed }.count
    }

    var followUpCount: Int {
        visibleIssues.filter { status(for: $0).isSent && !$0.hasVotePassed }.count
    }

    func radarInsights(for lens: CivicRadarLens) -> [CivicRadarInsight] {
        switch lens {
        case .personal:
            return radarInsights.filter { $0.issue.isPersonallyRelevant(to: profile) }
        case .actNow:
            return radarInsights.filter { $0.priority == .actNow }
        case .power:
            return radarInsights.sorted { lhs, rhs in
                if lhs.issue.trustScore != rhs.issue.trustScore {
                    return lhs.issue.trustScore > rhs.issue.trustScore
                }
                return lhs.score > rhs.score
            }
        case .social:
            return radarInsights.sorted {
                socialHeat(for: $0.issue.id) > socialHeat(for: $1.issue.id)
            }
        case .learn:
            return radarInsights.filter { $0.issue.impactLevel == .watch || $0.issue.trustScore < 80 }
        }
    }

    func socialHeat(for issueID: CivicIssue.ID) -> Int {
        socialPosts
            .filter { $0.issueID == issueID }
            .reduce(0) { total, post in
                total + post.reactions.total + post.commentCount * 2 + post.shareCount + post.likeCount
            }
    }

    func radarInsight(for issue: CivicIssue) -> CivicRadarInsight {
        let sent = status(for: issue).isSent
        let score = issue.radarScore(profile: profile, alreadySent: sent)
        let priority: CivicRadarPriority

        if sent {
            priority = .followUp
        } else if issue.hoursUntilVote <= 72 || issue.impactLevel == .urgent {
            priority = .actNow
        } else if score >= 48 {
            priority = .priority
        } else {
            priority = .watch
        }

        return CivicRadarInsight(
            issue: issue,
            priority: priority,
            score: score,
            reason: issue.personalReason(for: profile),
            recommendedAction: issue.recommendedAction(alreadySent: sent),
            timing: issue.timingSummary
        )
    }
}

extension CivicIssue {
    var hasVotePassed: Bool {
        voteDate.timeIntervalSinceNow < -3600
    }

    var timingSummary: String {
        if hasVotePassed {
            return "Vote window has passed. Watch for the outcome or official reply."
        }
        if hoursUntilVote <= 24 {
            return "Action window closes in \(voteCountdownLabel)."
        }
        if hoursUntilVote <= 72 {
            return "Worth filing before the vote in \(voteCountdownLabel)."
        }
        return "Upcoming \(voteDate.formatted(date: .abbreviated, time: .shortened))."
    }

    var trustScore: Int {
        if let trustScoreOverride {
            return max(0, min(100, trustScoreOverride))
        }
        var score = 58
        if !sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 10 }
        if !sourceDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 8 }
        score += min(facts.count, 3) * 6
        if sourceURLValue != nil { score += 8 }
        return min(score, 96)
    }

    var trustLabel: String {
        if trustScore >= 88 { return "High source confidence" }
        if trustScore >= 76 { return "Source-backed" }
        return "Needs review"
    }

    var sourceEvidenceText: String {
        var parts: [String] = []
        if let sourceHost, !sourceHost.isEmpty {
            parts.append(sourceHost)
        } else if let host = sourceURLValue?.host {
            parts.append(host.replacingOccurrences(of: "www.", with: ""))
        }
        parts.append("\(facts.count) extracted facts")
        if !citations.isEmpty {
            parts.append("\(citations.count) citations")
        }
        if let extractionConfidence {
            parts.append("\(Int(extractionConfidence.rounded()))% parser confidence")
        }
        return parts.joined(separator: " · ")
    }

    var sourceURLValue: URL? {
        guard let sourceURL,
              let url = URL(string: sourceURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return nil }
        return url
    }

    func isPersonallyRelevant(to profile: UserProfile?) -> Bool {
        guard let profile else { return false }
        if !topics.intersection(profile.interests).isEmpty { return true }
        if profile.factors.contains(where: { !$0.topics.isDisjoint(with: topics) }) { return true }
        return scope.matches(profile: profile)
    }

    func actionTimeEstimate(alreadySent: Bool) -> String {
        if alreadySent { return "30 sec follow-up" }
        if hasVotePassed { return "1 min recap" }
        if hoursUntilVote <= 24 { return "2 min file" }
        if hoursUntilVote <= 72 { return "5 min action" }
        if impactLevel == .watch { return "60 sec learn" }
        return "3 min review"
    }

    func civicLoopStep(alreadySent: Bool) -> String {
        if alreadySent { return "See impact" }
        if hasVotePassed { return "Track outcome" }
        if hoursUntilVote <= 72 || impactLevel == .urgent { return "Act" }
        if trustScore < 76 { return "Verify" }
        return "Understand"
    }

    var powerMap: CivicPowerMap {
        let venue: String
        switch scope {
        case .localPhilly:
            venue = "City-level agenda"
        case .state:
            venue = "State legislature"
        case .federal:
            venue = JurisdictionScope.isRegulatory(jurisdiction: jurisdiction, scope: scope)
                ? "Federal rulemaking"
                : "Federal legislation"
        }

        let channel: String
        if JurisdictionScope.isRegulatory(jurisdiction: jurisdiction, scope: scope) {
            channel = "Public comment or source docket"
        } else {
            channel = "Representative contact route"
        }

        let pressure: String
        if hoursUntilVote <= 24 && !hasVotePassed {
            pressure = "Short window: file first, then mobilize."
        } else if hoursUntilVote <= 72 && !hasVotePassed {
            pressure = "Comment/vote window is close enough for pressure."
        } else if hasVotePassed {
            pressure = "Outcome tracking matters more than new filing."
        } else {
            pressure = "Best leverage is learning, saving, and sharing."
        }

        return CivicPowerMap(
            decisionMaker: official.name.isEmpty ? jurisdiction : official.name,
            venue: venue,
            publicChannel: channel,
            sourceSignal: "\(sourceName) · \(trustLabel)",
            pressurePoint: pressure
        )
    }

    func personalReason(for profile: UserProfile?) -> String {
        guard let profile else {
            return "Set your ZIP so \(AppBrand.name) can judge whether this touches your reps, neighborhood, and priorities."
        }

        let matchingTopics = topics.intersection(profile.interests)
        if let topic = matchingTopics.sorted(by: { $0.label < $1.label }).first {
            return "Matches your \(topic.label.lowercased()) priority in \(profile.displayLocation)."
        }

        let matchingFactors = profile.factors.filter { !$0.topics.isDisjoint(with: topics) }
        if let factor = matchingFactors.sorted(by: { $0.label < $1.label }).first {
            return "Relevant to your \(factor.label.lowercased()) profile in \(profile.displayLocation)."
        }

        switch scope {
        case .localPhilly:
            return "Local Philadelphia action routed to your city officials."
        case let .state(code):
            return "State-level item for \(code.uppercased()) residents."
        case .federal:
            return "Federal item that applies to every U.S. constituent."
        }
    }

    func recommendedAction(alreadySent: Bool) -> String {
        if alreadySent {
            return "Track reply and outcome"
        }
        if hasVotePassed {
            return "Watch outcome"
        }
        if hoursUntilVote <= 24 {
            return "File now, then rally your crew"
        }
        if hoursUntilVote <= 72 {
            return "File before the vote"
        }
        if impactLevel == .watch {
            return "Save or ask the assistant"
        }
        return "Review and decide"
    }

    func assistantActionPlanPrompt(profile: UserProfile?, alreadySent: Bool, rallyCount: Int) -> String {
        let context: String
        if let profile {
            let interests = profile.interests
                .sorted { $0.label < $1.label }
                .map(\.label)
                .joined(separator: ", ")
            let factors = profile.factors
                .sorted { $0.label < $1.label }
                .map(\.label)
                .joined(separator: ", ")

            context = """
            My location: \(profile.displayLocation)
            My interests: \(interests.isEmpty ? "not set" : interests)
            My civic context: \(factors.isEmpty ? "not set" : factors)
            """
        } else {
            context = "My location and profile are not set yet."
        }

        return """
        Build me a concrete civic action plan for this issue:

        Issue: \(title)
        Summary: \(summary)
        Jurisdiction: \(jurisdiction)
        Vote/comment timing: \(timingSummary)
        Why it may matter to me: \(personalReason(for: profile))
        Current status: \(alreadySent ? "I already filed; help me follow up." : "I have not filed yet.")
        Crew status: \(rallyCount) person\(rallyCount == 1 ? "" : "s") rallied so far.
        Source: \(sourceName), \(trustLabel)
        \(context)

        Please give me:
        1. the best next move in the next 10 minutes
        2. whether endorse or oppose seems more aligned with the facts, with caveats
        3. a short neighbor text I can send
        4. what to watch after the vote or comment window
        """
    }

    func radarScore(profile: UserProfile?, alreadySent: Bool) -> Int {
        var score = alreadySent ? -8 : 18

        switch impactLevel {
        case .urgent: score += 28
        case .material: score += 20
        case .watch: score += 10
        }

        if !hasVotePassed {
            if hoursUntilVote <= 24 { score += 34 }
            else if hoursUntilVote <= 72 { score += 26 }
            else if hoursUntilVote <= 168 { score += 14 }
        } else {
            score -= 28
        }

        if case .localPhilly = scope { score += 8 }

        if let profile {
            if !topics.intersection(profile.interests).isEmpty {
                score += 16
            }
            let factorMatches = profile.factors.filter { !$0.topics.isDisjoint(with: topics) }.count
            score += min(factorMatches * 7, 21)
        }

        return score
    }
}
