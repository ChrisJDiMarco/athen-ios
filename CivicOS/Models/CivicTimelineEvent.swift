import Foundation

/// One chronological event on a bill. Reporters use this to write the
/// "what happened with HB1429" piece; Hill staff use it to see where
/// the bill is in the pipeline. Generated server-side from issue history
/// + the VoteStore.
struct CivicTimelineEvent: Identifiable, Hashable, Decodable {
    /// Composite id (kind + atISO) is unique within one bill.
    var id: String { "\(kind.rawValue)-\(atISO)" }
    let kind: Kind
    let atISO: String
    let title: String
    let detail: String
    let voteId: String?

    enum Kind: String, Decodable, Hashable {
        case introduced
        case updated
        case voteScheduled = "vote-scheduled"
        case votePassedDate = "vote-passed-date"
        case rollCall = "roll-call"
    }

    enum CodingKeys: String, CodingKey {
        case kind, atISO, title, detail, voteId
    }
}

struct CivicTimelineResponse: Decodable {
    let issueId: String
    let events: [CivicTimelineEvent]
}
