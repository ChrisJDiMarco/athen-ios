import Foundation
import SwiftUI

/// Snapshot of a bookmarked bill at a moment in time. Local-first; lives in
/// UserDefaults keyed by issue id. Used by the diff watcher to detect
/// meaningful changes between launches.
struct BookmarkSnapshot: Codable, Equatable, Hashable {
    let issueID: UUID
    let title: String
    let summary: String
    let voteDateISO: String
    let updatedAtISO: String
    let capturedAt: Date

    init(from issue: CivicIssue, capturedAt: Date = .now) {
        self.issueID = issue.id
        self.title = issue.title
        self.summary = issue.summary
        let iso = ISO8601DateFormatter()
        self.voteDateISO = iso.string(from: issue.voteDate)
        // We don't have a true backend updatedAt on the iOS CivicIssue, so we
        // hash the meaningful fields and use that as the change signal.
        self.updatedAtISO = iso.string(from: capturedAt)
        self.capturedAt = capturedAt
    }

    /// Lightweight content hash used to detect change without storing the
    /// full bill text. If any of these change, the diff watcher fires.
    var contentSignature: String {
        "\(title)|\(summary)|\(voteDateISO)"
    }
}

/// One detected change on a bookmarked issue. Surfaced on the Home tab's
/// "What changed" card and on the issue detail.
struct CivicDiffEvent: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let issueID: UUID
    let issueTitle: String
    let detectedAt: Date
    let kind: Kind
    let oldValue: String
    let newValue: String
    /// Optional Claude-written plain-English explanation of what changed.
    var plainEnglish: String?

    enum Kind: String, Codable, Hashable {
        case summaryChanged
        case voteDateChanged
        case titleChanged

        var label: String {
            switch self {
            case .summaryChanged: "Summary updated"
            case .voteDateChanged: "Vote date changed"
            case .titleChanged: "Title changed"
            }
        }

        var systemImage: String {
            switch self {
            case .summaryChanged: "doc.text.fill"
            case .voteDateChanged: "calendar.badge.exclamationmark"
            case .titleChanged: "pencil.line"
            }
        }

        var tint: Color {
            switch self {
            case .summaryChanged: CivicTheme.cyan
            case .voteDateChanged: CivicTheme.amber
            case .titleChanged: CivicTheme.violet
            }
        }
    }

    init(
        id: UUID = UUID(),
        issueID: UUID,
        issueTitle: String,
        detectedAt: Date = .now,
        kind: Kind,
        oldValue: String,
        newValue: String,
        plainEnglish: String? = nil
    ) {
        self.id = id
        self.issueID = issueID
        self.issueTitle = issueTitle
        self.detectedAt = detectedAt
        self.kind = kind
        self.oldValue = oldValue
        self.newValue = newValue
        self.plainEnglish = plainEnglish
    }
}
