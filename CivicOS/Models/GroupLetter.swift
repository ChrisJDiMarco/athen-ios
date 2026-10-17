import Foundation

/// A shared letter that members of an OutreachGroup co-sign before sending.
/// Foundation level: lives entirely in local UserDefaults; sending integrates
/// with the existing filing dispatcher once we add a "send as group" flow.
struct GroupLetter: Identifiable, Codable, Hashable {
    let id: UUID
    let groupID: UUID
    let issueID: UUID
    let issueTitle: String
    var subject: String
    var body: String
    var signers: [GroupLetterSigner]
    let createdAt: Date
    var sentAt: Date?

    init(
        id: UUID = UUID(),
        groupID: UUID,
        issueID: UUID,
        issueTitle: String,
        subject: String,
        body: String,
        signers: [GroupLetterSigner] = [],
        createdAt: Date = .now,
        sentAt: Date? = nil
    ) {
        self.id = id
        self.groupID = groupID
        self.issueID = issueID
        self.issueTitle = issueTitle
        self.subject = subject
        self.body = body
        self.signers = signers
        self.createdAt = createdAt
        self.sentAt = sentAt
    }

    var isSent: Bool { sentAt != nil }
    var signerCount: Int { signers.count }
}

struct GroupLetterSigner: Identifiable, Codable, Hashable {
    let id: UUID
    let memberID: UUID?
    var name: String
    let signedAt: Date

    init(id: UUID = UUID(), memberID: UUID? = nil, name: String, signedAt: Date = .now) {
        self.id = id
        self.memberID = memberID
        self.name = name
        self.signedAt = signedAt
    }

    var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        let combined = (first + last).uppercased()
        return combined.isEmpty ? "?" : combined
    }
}
