import Foundation

/// Aggregate count of Athen users who've endorsed or opposed one issue.
/// Returned by GET /v1/issues/:id/tally. Tracks counts only — no identity.
struct IssueFilingTally: Decodable, Equatable {
    let endorseCount: Int
    let opposeCount: Int

    func incrementingEndorse() -> IssueFilingTally {
        IssueFilingTally(endorseCount: endorseCount + 1, opposeCount: opposeCount)
    }

    func incrementingOppose() -> IssueFilingTally {
        IssueFilingTally(endorseCount: endorseCount, opposeCount: opposeCount + 1)
    }
}
