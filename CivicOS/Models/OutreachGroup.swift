import Foundation

struct OutreachGroup: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var emoji: String
    var members: [GroupMember]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "✊",
        members: [GroupMember] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.members = members
        self.createdAt = createdAt
    }

    var totalRallies: Int {
        members.reduce(0) { $0 + $1.rallyEvents.count }
    }

    var activeMemberCount: Int {
        members.filter { !$0.rallyEvents.isEmpty }.count
    }
}

struct GroupMember: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var emoji: String
    var phoneOrHandle: String?
    var rallyEvents: [RallyEvent]
    var addedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "🙂",
        phoneOrHandle: String? = nil,
        rallyEvents: [RallyEvent] = [],
        addedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.phoneOrHandle = phoneOrHandle
        self.rallyEvents = rallyEvents
        self.addedAt = addedAt
    }

    var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        let combined = (first + last).uppercased()
        return combined.isEmpty ? "?" : combined
    }
}

struct RallyEvent: Identifiable, Hashable, Codable {
    let id: UUID
    let issueID: UUID
    let issueTitle: String
    let sentAt: Date

    init(id: UUID = UUID(), issueID: UUID, issueTitle: String, sentAt: Date = .now) {
        self.id = id
        self.issueID = issueID
        self.issueTitle = issueTitle
        self.sentAt = sentAt
    }
}
