import Foundation
import SwiftUI

/// The Claude-generated, source-grounded brief for a specific civic item.
/// Mirrors backend BriefAnalysis exactly.
struct CivicBriefAnalysis: Equatable, Hashable, Decodable {
    let sourceFingerprint: String
    let generatedAt: Date
    let model: String
    let headline: String
    let subhead: String
    let lead: String
    let keyFacts: [KeyFact]
    let twoSides: [Side]
    let fiscalImpact: String
    let timeline: [TimelineEntry]
    let cohortProjections: [CohortProjection]
    let recommendedAction: String
    let confidence: Confidence
    let pullQuote: String?
    let sourceLine: String

    struct KeyFact: Equatable, Hashable, Decodable, Identifiable {
        var id: String { label }
        let label: String
        let value: String
    }

    struct Side: Equatable, Hashable, Decodable, Identifiable {
        var id: String { stance.rawValue + "|" + headline }
        let stance: Stance
        let headline: String
        let argument: String
        let who: String

        enum Stance: String, Decodable {
            case support, concern, watch

            var label: String {
                switch self {
                case .support: "Supporters"
                case .concern: "Critics"
                case .watch: "Watch for"
                }
            }

            var systemImage: String {
                switch self {
                case .support: "checkmark.seal.fill"
                case .concern: "exclamationmark.triangle.fill"
                case .watch: "eye.fill"
                }
            }

            var tint: Color {
                switch self {
                case .support: CivicTheme.green
                case .concern: CivicTheme.amber
                case .watch: CivicTheme.cyan
                }
            }
        }
    }

    struct TimelineEntry: Equatable, Hashable, Decodable, Identifiable {
        var id: String { dateISO + label }
        let dateISO: String
        let label: String

        var date: Date? {
            if let d = ISO8601DateFormatter().date(from: dateISO) { return d }
            let lenient = DateFormatter()
            lenient.dateFormat = "yyyy-MM-dd"
            return lenient.date(from: dateISO)
        }
    }

    struct CohortProjection: Equatable, Hashable, Decodable, Identifiable {
        var id: String { cohort.rawValue + impact }
        let cohort: Cohort
        let impact: String

        enum Cohort: String, Decodable {
            case renter, homeowner, parent, commuter, businessOwner
            case lowIncome, olderAdult, general

            var label: String {
                switch self {
                case .renter: "Renters"
                case .homeowner: "Homeowners"
                case .parent: "Parents"
                case .commuter: "Commuters"
                case .businessOwner: "Business owners"
                case .lowIncome: "Lower-income households"
                case .olderAdult: "Older adults"
                case .general: "Everyone"
                }
            }

            var systemImage: String {
                switch self {
                case .renter: "key.fill"
                case .homeowner: "house.fill"
                case .parent: "figure.and.child.holdinghands"
                case .commuter: "tram.fill"
                case .businessOwner: "briefcase.fill"
                case .lowIncome: "heart.text.square.fill"
                case .olderAdult: "figure.walk.circle.fill"
                case .general: "person.2.fill"
                }
            }

            var tint: Color {
                switch self {
                case .renter: CivicTheme.violet
                case .homeowner: CivicTheme.amber
                case .parent: CivicTheme.green
                case .commuter: CivicTheme.cyan
                case .businessOwner: CivicTheme.amber
                case .lowIncome: CivicTheme.green
                case .olderAdult: CivicTheme.violet
                case .general: CivicTheme.cyan
                }
            }
        }
    }

    struct Confidence: Equatable, Hashable, Decodable {
        let label: Label
        let reason: String

        enum Label: String, Decodable {
            case high, medium, low

            var display: String {
                switch self {
                case .high: "High confidence"
                case .medium: "Medium confidence"
                case .low: "Early read"
                }
            }

            var tint: Color {
                switch self {
                case .high: CivicTheme.green
                case .medium: CivicTheme.cyan
                case .low: CivicTheme.amber
                }
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case sourceFingerprint, model, headline, subhead, lead
        case keyFacts, twoSides, fiscalImpact, timeline, cohortProjections
        case recommendedAction, confidence, pullQuote, sourceLine
        case generatedAtISO
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceFingerprint = try c.decode(String.self, forKey: .sourceFingerprint)
        model = try c.decode(String.self, forKey: .model)
        headline = try c.decode(String.self, forKey: .headline)
        subhead = try c.decode(String.self, forKey: .subhead)
        lead = try c.decode(String.self, forKey: .lead)
        keyFacts = (try? c.decode([KeyFact].self, forKey: .keyFacts)) ?? []
        twoSides = (try? c.decode([Side].self, forKey: .twoSides)) ?? []
        fiscalImpact = try c.decode(String.self, forKey: .fiscalImpact)
        timeline = (try? c.decode([TimelineEntry].self, forKey: .timeline)) ?? []
        cohortProjections = (try? c.decode([CohortProjection].self, forKey: .cohortProjections)) ?? []
        recommendedAction = try c.decode(String.self, forKey: .recommendedAction)
        confidence = try c.decode(Confidence.self, forKey: .confidence)
        pullQuote = try? c.decodeIfPresent(String.self, forKey: .pullQuote)
        sourceLine = try c.decode(String.self, forKey: .sourceLine)
        let raw = try c.decode(String.self, forKey: .generatedAtISO)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        generatedAt = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) ?? .now
    }
}

/// One issue + its (possibly missing) brief, as returned by /v1/brief.
struct CivicBriefDigestItem: Equatable, Hashable, Decodable, Identifiable {
    var id: String { issueId }
    let issueId: String
    let issue: BriefIssueRef
    let brief: CivicBriefAnalysis?

    init(issueId: String, issue: BriefIssueRef, brief: CivicBriefAnalysis?) {
        self.issueId = issueId
        self.issue = issue
        self.brief = brief
    }
}

struct BriefIssueRef: Equatable, Hashable, Decodable {
    let id: String
    let title: String
    let category: String
    let jurisdiction: String
    let scope: String
    let stateCode: String?
    let summary: String
    let impactLevel: String
    let voteDateISO: String
    let sourceName: String
    let sourceHost: String?
    let sourceURL: String?
    let trustScore: Int?

    var voteDate: Date? {
        ISO8601DateFormatter().date(from: voteDateISO)
    }
}

struct CivicBriefDigest: Equatable, Decodable {
    let generatedAt: Date
    let items: [CivicBriefDigestItem]
    let cacheStats: CacheStats?

    struct CacheStats: Equatable, Decodable { let cached: Int }

    init(generatedAt: Date, items: [CivicBriefDigestItem], cacheStats: CacheStats?) {
        self.generatedAt = generatedAt
        self.items = items
        self.cacheStats = cacheStats
    }

    enum CodingKeys: String, CodingKey { case generatedAtISO, items, cacheStats }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .generatedAtISO)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        generatedAt = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) ?? .now
        items = try c.decode([CivicBriefDigestItem].self, forKey: .items)
        cacheStats = try? c.decodeIfPresent(CacheStats.self, forKey: .cacheStats)
    }
}

struct CivicAudioBriefing: Equatable, Decodable {
    let generatedAt: Date
    let script: String
    let audio: AudioPayload
    let issueIds: [String]

    enum AudioPayload: Equatable, Decodable {
        case elevenlabs(base64: String, contentType: String, bytes: Int)
        case clientFallback(reason: String)

        private enum Keys: String, CodingKey { case provider, base64, contentType, bytes, reason }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            let provider = try c.decode(String.self, forKey: .provider)
            switch provider {
            case "elevenlabs":
                self = .elevenlabs(
                    base64: try c.decode(String.self, forKey: .base64),
                    contentType: try c.decode(String.self, forKey: .contentType),
                    bytes: try c.decode(Int.self, forKey: .bytes)
                )
            default:
                self = .clientFallback(reason: (try? c.decode(String.self, forKey: .reason)) ?? "")
            }
        }
    }

    enum CodingKeys: String, CodingKey { case generatedAtISO, script, audio, issueIds }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .generatedAtISO)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        generatedAt = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) ?? .now
        script = try c.decode(String.self, forKey: .script)
        audio = try c.decode(AudioPayload.self, forKey: .audio)
        issueIds = (try? c.decode([String].self, forKey: .issueIds)) ?? []
    }
}
