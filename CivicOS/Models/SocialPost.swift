import Foundation
import SwiftUI

enum SocialPostKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case discussion
    case aiBrief
    case filed
    case rally
    case event
    case poll
    case explainer
    case question

    var id: String { rawValue }

    var label: String {
        switch self {
        case .discussion: "Discussion"
        case .aiBrief: "AI Brief"
        case .filed: "Filed"
        case .rally: "Rally"
        case .event: "Event"
        case .poll: "Poll"
        case .explainer: "Explainer"
        case .question: "Question"
        }
    }

    var systemImage: String {
        switch self {
        case .discussion: "bubble.left.and.bubble.right.fill"
        case .aiBrief: "sparkles"
        case .filed: "paperplane.fill"
        case .rally: "person.3.fill"
        case .event: "calendar.badge.clock"
        case .poll: "chart.bar.fill"
        case .explainer: "text.bubble.fill"
        case .question: "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .discussion: CivicTheme.cyan
        case .aiBrief: CivicTheme.violet
        case .filed: CivicTheme.green
        case .rally: CivicTheme.violet
        case .event: CivicTheme.amber
        case .poll: CivicTheme.violet
        case .explainer: CivicTheme.cyan
        case .question: CivicTheme.amber
        }
    }
}

/// RSVP options for `.event` posts. Mirrors Eventbrite/Meetup-style 3-state.
enum EventRSVPKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case going, interested, cantGo

    var id: String { rawValue }
    var label: String {
        switch self {
        case .going: "Going"
        case .interested: "Interested"
        case .cantGo: "Can't go"
        }
    }
    var systemImage: String {
        switch self {
        case .going: "checkmark.circle.fill"
        case .interested: "star.fill"
        case .cantGo: "xmark.circle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .going: CivicTheme.green
        case .interested: CivicTheme.amber
        case .cantGo: CivicTheme.quietInk
        }
    }
}

struct EventRSVPTallies: Codable, Hashable {
    var going: Int = 0
    var interested: Int = 0
    var cantGo: Int = 0

    func count(_ kind: EventRSVPKind) -> Int {
        switch kind {
        case .going: going
        case .interested: interested
        case .cantGo: cantGo
        }
    }
    var total: Int { going + interested + cantGo }
}

/// One option in a poll. Vote count is summed across all installs in v1.1;
/// in v1 it's local-only (your vote bumps the count).
struct PollOption: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var voteCount: Int

    init(id: UUID = UUID(), text: String, voteCount: Int = 0) {
        self.id = id
        self.text = text
        self.voteCount = voteCount
    }
}

struct AIExplainer: Hashable, Codable {
    var headline: String
    var plainEnglish: String
    var stakes: String
    var positions: [ExplainerPosition]
    var nextStep: String
    var visualPrompt: String
    var sourceLine: String
    var confidenceLabel: String
}

struct ExplainerPosition: Hashable, Codable, Identifiable {
    var id: String { "\(kind.rawValue)|\(title)" }
    var kind: ExplainerPositionKind
    var title: String
    var summary: String
}

enum ExplainerPositionKind: String, Codable, Hashable {
    case support
    case concern
    case watch

    var label: String {
        switch self {
        case .support: "Why supporters like it"
        case .concern: "What critics worry about"
        case .watch: "What to watch"
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

/// Three civic-specific reactions that map to Athen's core social loop:
/// agree publicly, commit to act, amplify off-platform. Raw values are
/// pinned to legacy strings so existing persisted posts decode unchanged.
enum CivicReactionKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case coSign = "willFile"
    case imIn = "needHelp"
    case boost = "disagree"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .coSign: "Co-sign"
        case .imIn: "I'm in"
        case .boost: "Boost"
        }
    }

    var shortLabel: String {
        switch self {
        case .coSign: "Co-sign"
        case .imIn: "I'm in"
        case .boost: "Boost"
        }
    }

    var systemImage: String {
        switch self {
        case .coSign: "hand.thumbsup.fill"
        case .imIn: "hand.raised.fill"
        case .boost: "arrow.up.forward.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .coSign: CivicTheme.green
        case .imIn: CivicTheme.violet
        case .boost: CivicTheme.cyan
        }
    }
}

struct CivicReactionTallies: Codable, Hashable {
    var willFile: Int
    var needHelp: Int
    var disagree: Int

    init(willFile: Int = 0, needHelp: Int = 0, disagree: Int = 0) {
        self.willFile = willFile
        self.needHelp = needHelp
        self.disagree = disagree
    }

    func count(_ kind: CivicReactionKind) -> Int {
        switch kind {
        case .coSign: willFile
        case .imIn: needHelp
        case .boost: disagree
        }
    }

    var total: Int { willFile + needHelp + disagree }
}

struct SocialPost: Identifiable, Hashable, Codable {
    let id: UUID
    var authorName: String
    var authorHandle: String
    var authorEmoji: String
    var body: String
    var kind: SocialPostKind
    var issueID: CivicIssue.ID?
    var issueTitle: String?
    var locality: String
    var explainer: AIExplainer?
    var imageData: Data?
    var createdAt: Date
    var likeCount: Int
    var commentCount: Int
    var shareCount: Int
    var likedByMe: Bool
    var reactions: CivicReactionTallies
    var myReaction: CivicReactionKind?

    // — New in v1.1 —
    /// Reference to another post being reposted. UI renders that post inline
    /// + this post's body as the commenter's note.
    var repostOfID: UUID?
    /// Anchored to top of City scope when true. Used for community
    /// announcements (city council, moderator-pinned).
    var isPinned: Bool
    /// For `.event` posts: when it happens, plus RSVP tallies + your pick.
    var eventDateISO: String?
    var eventRSVPs: EventRSVPTallies
    var myRsvp: EventRSVPKind?
    /// For `.poll` posts: 2-4 options the author defined. `myPollVote` is the
    /// option ID you voted for (nil = haven't voted yet).
    var pollOptions: [PollOption]?
    var myPollVote: UUID?

    init(
        id: UUID = UUID(),
        authorName: String,
        authorHandle: String,
        authorEmoji: String,
        body: String,
        kind: SocialPostKind,
        issueID: CivicIssue.ID? = nil,
        issueTitle: String? = nil,
        locality: String,
        explainer: AIExplainer? = nil,
        imageData: Data? = nil,
        createdAt: Date = .now,
        likeCount: Int = 0,
        commentCount: Int = 0,
        shareCount: Int = 0,
        likedByMe: Bool = false,
        reactions: CivicReactionTallies = .init(),
        myReaction: CivicReactionKind? = nil,
        repostOfID: UUID? = nil,
        isPinned: Bool = false,
        eventDateISO: String? = nil,
        eventRSVPs: EventRSVPTallies = .init(),
        myRsvp: EventRSVPKind? = nil,
        pollOptions: [PollOption]? = nil,
        myPollVote: UUID? = nil
    ) {
        self.id = id
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.authorEmoji = authorEmoji
        self.body = body
        self.kind = kind
        self.issueID = issueID
        self.issueTitle = issueTitle
        self.locality = locality
        self.explainer = explainer
        self.imageData = imageData
        self.createdAt = createdAt
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.shareCount = shareCount
        self.likedByMe = likedByMe
        self.reactions = reactions
        self.myReaction = myReaction
        self.repostOfID = repostOfID
        self.isPinned = isPinned
        self.eventDateISO = eventDateISO
        self.eventRSVPs = eventRSVPs
        self.myRsvp = myRsvp
        self.pollOptions = pollOptions
        self.myPollVote = myPollVote
    }

    enum CodingKeys: String, CodingKey {
        case id, authorName, authorHandle, authorEmoji, body, kind
        case issueID, issueTitle, locality, explainer, imageData, createdAt
        case likeCount, commentCount, shareCount, likedByMe
        case reactions, myReaction
        case repostOfID, isPinned, eventDateISO, eventRSVPs, myRsvp
        case pollOptions, myPollVote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        authorName = try c.decode(String.self, forKey: .authorName)
        authorHandle = try c.decode(String.self, forKey: .authorHandle)
        authorEmoji = try c.decode(String.self, forKey: .authorEmoji)
        body = try c.decode(String.self, forKey: .body)
        kind = try c.decode(SocialPostKind.self, forKey: .kind)
        issueID = try? c.decodeIfPresent(CivicIssue.ID.self, forKey: .issueID)
        issueTitle = try? c.decodeIfPresent(String.self, forKey: .issueTitle)
        locality = try c.decode(String.self, forKey: .locality)
        explainer = try? c.decodeIfPresent(AIExplainer.self, forKey: .explainer)
        imageData = try? c.decodeIfPresent(Data.self, forKey: .imageData)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        likeCount = (try? c.decode(Int.self, forKey: .likeCount)) ?? 0
        commentCount = (try? c.decode(Int.self, forKey: .commentCount)) ?? 0
        shareCount = (try? c.decode(Int.self, forKey: .shareCount)) ?? 0
        likedByMe = (try? c.decode(Bool.self, forKey: .likedByMe)) ?? false
        reactions = (try? c.decode(CivicReactionTallies.self, forKey: .reactions)) ?? .init()
        myReaction = try? c.decodeIfPresent(CivicReactionKind.self, forKey: .myReaction)
        repostOfID = try? c.decodeIfPresent(UUID.self, forKey: .repostOfID)
        isPinned = (try? c.decode(Bool.self, forKey: .isPinned)) ?? false
        eventDateISO = try? c.decodeIfPresent(String.self, forKey: .eventDateISO)
        eventRSVPs = (try? c.decode(EventRSVPTallies.self, forKey: .eventRSVPs)) ?? .init()
        myRsvp = try? c.decodeIfPresent(EventRSVPKind.self, forKey: .myRsvp)
        pollOptions = try? c.decodeIfPresent([PollOption].self, forKey: .pollOptions)
        myPollVote = try? c.decodeIfPresent(UUID.self, forKey: .myPollVote)
    }

    var eventDate: Date? {
        guard let iso = eventDateISO else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }
}

extension SocialPost {
    /// Seed posts for the Square (social) tab. AI Briefs no longer live here —
    /// they belong in the Brief tab. Square is pure community signal.
    static func samplePosts(issues: [CivicIssue]) -> [SocialPost] {
        let broadStreet = issues.first { $0.title.localizedCaseInsensitiveContains("Broad Street") }
        let schoolLunch = issues.first { $0.title.localizedCaseInsensitiveContains("School Lunch") }
        let energy = issues.first { $0.title.localizedCaseInsensitiveContains("Clean Energy") }
        _ = issues.first { $0.title.localizedCaseInsensitiveContains("Broadband") }

        return [
            SocialPost(
                authorName: "Maya",
                authorHandle: "@maya.phl",
                authorEmoji: "🏙️",
                body: "Filed on the Broad Street rezoning vote. The 30-second summary helped me send something clear instead of doom-scrolling council PDFs.",
                kind: .filed,
                issueID: broadStreet?.id,
                issueTitle: broadStreet?.title ?? "Broad Street Re-Zoning",
                locality: "Philadelphia",
                createdAt: .now.addingTimeInterval(-42 * 60),
                likeCount: 28,
                commentCount: 6,
                shareCount: 4,
                reactions: .init(willFile: 11, needHelp: 3, disagree: 2)
            ),
            SocialPost(
                authorName: "Chris",
                authorHandle: "@blockcaptain",
                authorEmoji: "✊",
                body: "Rallied five neighbors before the vote window closes. The group text was easier when everyone could open the same issue card.",
                kind: .rally,
                issueID: broadStreet?.id,
                issueTitle: broadStreet?.title ?? "Broad Street Re-Zoning",
                locality: "South Philly",
                createdAt: .now.addingTimeInterval(-2 * 3600),
                likeCount: 44,
                commentCount: 11,
                shareCount: 9,
                reactions: .init(willFile: 18, needHelp: 5, disagree: 1)
            ),
            SocialPost(
                authorName: "Ari",
                authorHandle: "@ariasks",
                authorEmoji: "🤔",
                body: "Can someone explain the tradeoff on the school lunch procurement item? I get the local vendor angle, but I want to understand the cost piece.",
                kind: .question,
                issueID: schoolLunch?.id,
                issueTitle: schoolLunch?.title ?? "School Lunch Procurement",
                locality: "Pennsylvania",
                createdAt: .now.addingTimeInterval(-5 * 3600),
                likeCount: 13,
                commentCount: 8,
                shareCount: 2,
                reactions: .init(willFile: 2, needHelp: 14, disagree: 0)
            ),
            SocialPost(
                authorName: "Nora",
                authorHandle: "@nora.energy",
                authorEmoji: "🌱",
                body: "The clean energy permitting card is a good example of why source confidence matters. I checked the source, then saved it for a longer read.",
                kind: .explainer,
                issueID: energy?.id,
                issueTitle: energy?.title ?? "Clean Energy Permitting",
                locality: "Federal",
                createdAt: .now.addingTimeInterval(-9 * 3600),
                likeCount: 31,
                commentCount: 4,
                shareCount: 6,
                reactions: .init(willFile: 7, needHelp: 4, disagree: 3)
            )
        ]
    }
}
