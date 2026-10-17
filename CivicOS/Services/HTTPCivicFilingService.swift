import Foundation

struct HTTPCivicFilingService: CivicFilingServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval
    /// Optional Gmail-routing hint. The store sets these when the user has
    /// the "Send from my Gmail" toggle on AND the Gmail integration is live.
    /// When set, send() includes them so the backend routes through Composio.
    var gmailEntityID: String?
    var useUserGmail: Bool

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 90, gmailEntityID: String? = nil, useUserGmail: Bool = false) {
        // Default 90s — Claude drafts take 8-15s typical, 25s tail when GovInfo
        // enrichment kicks in. 30s left users staring at a spinner that timed
        // out before Claude finished. Send is faster (already-drafted), but we
        // use the same generous budget for safety.
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
        self.gmailEntityID = gmailEntityID
        self.useUserGmail = useUserGmail
    }

    func draft(
        _ action: CivicAction,
        for issue: CivicIssue,
        from address: String
    ) async throws -> DraftedFiling {
        let url = baseURL.appendingPathComponent("v1/file/draft")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = FileRequest(
            action: action == .endorse ? "endorse" : "oppose",
            address: address,
            issue: FileRequest.Issue(from: issue),
            message: nil
        )
        request.httpBody = try makeEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, body: data)

        let decoded = try JSONDecoder().decode(DraftResponse.self, from: data)
        let channel = FilingChannel(rawValue: decoded.official.channel ?? "email") ?? .email
        return DraftedFiling(
            action: action,
            issue: issue,
            address: address,
            message: DraftedFilingMessage(subject: decoded.draft.subject, body: decoded.draft.body),
            official: DraftedFilingOfficial(
                name: decoded.official.name,
                title: decoded.official.title,
                district: decoded.official.district,
                source: decoded.official.source,
                channel: channel,
                contactFormURL: decoded.official.contactFormURL
            ),
            verifiedAddress: decoded.verifiedAddress
        )
    }

    func send(_ draft: DraftedFiling) async throws -> FilingReceipt {
        let url = baseURL.appendingPathComponent("v1/file/send")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = FileRequest(
            action: draft.action == .endorse ? "endorse" : "oppose",
            address: draft.address,
            issue: FileRequest.Issue(from: draft.issue),
            message: FileRequest.Message(subject: draft.message.subject, body: draft.message.body),
            useUserGmail: useUserGmail ? true : nil,
            entityId: useUserGmail ? gmailEntityID : nil
        )
        request.httpBody = try makeEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, body: data)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FileResponse.self, from: data)

        let channel = FilingChannel(rawValue: decoded.delivery?.channel ?? "email") ?? draft.official.channel
        return FilingReceipt(
            action: draft.action,
            sentAt: decoded.receipt.sentAt,
            officialName: decoded.receipt.officialName,
            confirmationCode: decoded.receipt.confirmationCode,
            messagePreview: decoded.receipt.messagePreview,
            channel: channel,
            statusNote: decoded.delivery?.statusNote ?? "",
            queued: decoded.delivery?.queued ?? false,
            dryRun: decoded.delivery?.dryRun ?? false
        )
    }

    func file(
        _ action: CivicAction,
        for issue: CivicIssue,
        from verifiedAddress: String,
        district _: String
    ) async throws -> FilingReceipt {
        let draft = try await draft(action, for: issue, from: verifiedAddress)
        return try await send(draft)
    }

    private func ensureSuccess(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CivicFilingError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: body)
            let code = decoded?.error.code ?? ""
            let raw = decoded?.error.message ?? "Filing failed."
            let friendly = friendlyMessage(for: http.statusCode, code: code, raw: raw)
            throw CivicFilingError.server(status: http.statusCode, message: friendly)
        }
    }

    private func friendlyMessage(for status: Int, code: String, raw: String) -> String {
        switch (status, code) {
        case (401, _):
            return "Couldn't reach the backend (auth). Reopen Athen and try again."
        case (429, "daily_quota_exceeded"), (429, "quota_exceeded"):
            return "You've hit today's free generation limit. It resets at midnight UTC."
        case (429, _):
            return "Athen is rate-limiting requests right now. Try again in a minute."
        case (502, _), (503, _), (504, _):
            return "Backend is having trouble (\(status)). Try again in a moment."
        default:
            return raw
        }
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

enum CivicFilingError: LocalizedError {
    case invalidResponse
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Backend returned an unexpected response."
        case let .server(_, message):
            message
        }
    }
}

private struct FileRequest: Encodable {
    let action: String
    let address: String
    let issue: Issue
    let message: Message?
    let useUserGmail: Bool?
    let entityId: String?

    init(action: String, address: String, issue: Issue, message: Message?, useUserGmail: Bool? = nil, entityId: String? = nil) {
        self.action = action
        self.address = address
        self.issue = issue
        self.message = message
        self.useUserGmail = useUserGmail
        self.entityId = entityId
    }

    struct Issue: Encodable {
        let id: String
        let title: String
        let category: String
        let jurisdiction: String
        let sourceName: String
        let summary: String
        let facts: [Fact]
        let voteDateISO: String

        struct Fact: Encodable {
            let label: String
            let value: String
        }

        init(from issue: CivicIssue) {
            let formatter = ISO8601DateFormatter()
            id = issue.id.uuidString
            title = issue.title
            category = issue.category
            jurisdiction = issue.jurisdiction
            sourceName = issue.sourceName
            summary = issue.summary
            facts = issue.facts.map { Fact(label: $0.label, value: $0.value) }
            voteDateISO = formatter.string(from: issue.voteDate)
        }
    }

    struct Message: Encodable {
        let subject: String
        let body: String
    }
}

private struct DraftResponse: Decodable {
    let draft: Draft
    let official: Official
    let verifiedAddress: String

    struct Draft: Decodable {
        let subject: String
        let body: String
    }

    struct Official: Decodable {
        let name: String
        let title: String
        let district: String
        let source: String
        let channel: String?
        let contactFormURL: String?
    }
}

private struct FileResponse: Decodable {
    let receipt: Receipt
    let delivery: Delivery?
    let verifiedAddress: String

    struct Receipt: Decodable {
        let action: String
        let sentAt: Date
        let officialName: String
        let confirmationCode: String
        let messagePreview: String
    }

    struct Delivery: Decodable {
        let channel: String
        let trackingId: String
        let deliveredTo: String
        let queued: Bool
        let dryRun: Bool
        let statusNote: String
    }
}

private struct ErrorResponse: Decodable {
    let error: ErrorBody

    struct ErrorBody: Decodable {
        let code: String
        let message: String
    }
}
