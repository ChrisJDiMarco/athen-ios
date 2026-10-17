import Foundation

struct DraftedFilingMessage: Equatable, Hashable {
    var subject: String
    var body: String
}

enum FilingChannel: String, Codable, Hashable {
    case email
    case contactFormQueue = "contact-form-queue"
    /// Logged locally in your history only — direct delivery to the official's
    /// office is rolling out in a later release. Used while Athen is in
    /// public-beta and Postmark/Composio aren't fully wired.
    case recordedLocal = "recorded-local"

    var displayLabel: String {
        switch self {
        case .email: "Direct email"
        case .contactFormQueue: "Contact form (queued)"
        case .recordedLocal: "Recorded in your history"
        }
    }
}

struct DraftedFilingOfficial: Equatable, Hashable {
    let name: String
    let title: String
    let district: String
    let source: String
    let channel: FilingChannel
    let contactFormURL: String?
}

struct DraftedFiling: Equatable, Hashable {
    let action: CivicAction
    let issue: CivicIssue
    let address: String
    var message: DraftedFilingMessage
    let official: DraftedFilingOfficial
    let verifiedAddress: String
}

protocol CivicFilingServicing {
    /// AI-drafts the message + resolves the official, but doesn't send.
    /// User can edit `message.body` before calling `send`.
    func draft(
        _ action: CivicAction,
        for issue: CivicIssue,
        from address: String
    ) async throws -> DraftedFiling

    /// Sends the (possibly edited) drafted message. The backend re-resolves the
    /// official server-side so the destination can't be tampered with.
    func send(_ draft: DraftedFiling) async throws -> FilingReceipt

    /// Legacy one-shot path. Kept for callers (previews/tests) that want fire-and-forget.
    func file(
        _ action: CivicAction,
        for issue: CivicIssue,
        from verifiedAddress: String,
        district: String
    ) async throws -> FilingReceipt
}

struct MockCivicFilingService: CivicFilingServicing {
    func draft(
        _ action: CivicAction,
        for issue: CivicIssue,
        from address: String
    ) async throws -> DraftedFiling {
        try await Task.sleep(nanoseconds: 600_000_000)

        let body = """
        I am a verified constituent in Philadelphia District 4 (ZIP \(issue.zipCode.isEmpty ? "—" : issue.zipCode)). I \(action.formalVerb) \(issue.title).

        \(issue.facts.first?.value ?? "")

        Please record my position as part of the public record for \(issue.sourceName).
        """

        let isFederal: Bool
        if case .federal = issue.scope { isFederal = true } else { isFederal = false }

        return DraftedFiling(
            action: action,
            issue: issue,
            address: address,
            message: DraftedFilingMessage(
                subject: "Constituent position on \(issue.title)",
                body: body
            ),
            official: DraftedFilingOfficial(
                name: issue.official.name,
                title: issue.official.title,
                district: issue.official.district,
                source: "mock",
                channel: isFederal ? .contactFormQueue : .email,
                contactFormURL: isFederal ? "https://example.senate.gov/contact" : nil
            ),
            verifiedAddress: address.isEmpty ? "Demo address, Philadelphia, PA 19129" : address
        )
    }

    func send(_ draft: DraftedFiling) async throws -> FilingReceipt {
        try await Task.sleep(nanoseconds: 600_000_000)
        let reference = "COS-\(Int.random(in: 2300...9899))"
        let queued = draft.official.channel == .contactFormQueue
        return FilingReceipt(
            action: draft.action,
            sentAt: .now,
            officialName: draft.official.name,
            confirmationCode: reference,
            messagePreview: firstParagraph(draft.message.body),
            channel: draft.official.channel,
            statusNote: queued
                ? "Queued for \(draft.official.name)'s public contact form. We'll submit it within the next hour."
                : "Delivered via email to \(draft.official.name).",
            queued: queued,
            dryRun: false
        )
    }

    func file(
        _ action: CivicAction,
        for issue: CivicIssue,
        from verifiedAddress: String,
        district: String
    ) async throws -> FilingReceipt {
        let draft = try await draft(action, for: issue, from: verifiedAddress)
        _ = district
        return try await send(draft)
    }

    private func firstParagraph(_ body: String) -> String {
        let segments = body.split(separator: "\n", omittingEmptySubsequences: true)
        return String(segments.first ?? Substring(body)).trimmingCharacters(in: .whitespaces)
    }
}
