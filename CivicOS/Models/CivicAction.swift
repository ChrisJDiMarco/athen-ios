import Foundation

enum CivicAction: String, CaseIterable, Codable, Hashable, Identifiable {
    case endorse = "Endorse"
    case oppose = "Oppose"

    var id: String { rawValue }

    var formalVerb: String {
        switch self {
        case .endorse:
            "support"
        case .oppose:
            "oppose"
        }
    }

    var systemImage: String {
        switch self {
        case .endorse:
            "checkmark.seal.fill"
        case .oppose:
            "xmark.seal.fill"
        }
    }
}

enum FilingStatus: Equatable, Hashable {
    case ready
    case drafting(CivicAction)
    case sending(CivicAction)
    case sent(FilingReceipt)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .drafting, .sending: return true
        case .ready, .sent, .failed: return false
        }
    }

    var isSent: Bool {
        if case .sent = self {
            true
        } else {
            false
        }
    }

    var receipt: FilingReceipt? {
        if case let .sent(receipt) = self {
            receipt
        } else {
            nil
        }
    }
}

struct FilingReceipt: Equatable, Hashable, Identifiable, Codable {
    var id: String { confirmationCode }

    let action: CivicAction
    let sentAt: Date
    let officialName: String
    let confirmationCode: String
    let messagePreview: String
    let channel: FilingChannel
    let statusNote: String
    let queued: Bool
    let dryRun: Bool

    init(
        action: CivicAction,
        sentAt: Date,
        officialName: String,
        confirmationCode: String,
        messagePreview: String,
        channel: FilingChannel = .email,
        statusNote: String = "",
        queued: Bool = false,
        dryRun: Bool = false
    ) {
        self.action = action
        self.sentAt = sentAt
        self.officialName = officialName
        self.confirmationCode = confirmationCode
        self.messagePreview = messagePreview
        self.channel = channel
        self.statusNote = statusNote
        self.queued = queued
        self.dryRun = dryRun
    }
}
