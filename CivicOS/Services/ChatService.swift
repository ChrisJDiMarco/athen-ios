import Foundation

protocol ChatServicing {
    func stream(
        messages: [ChatMessage],
        profile: UserProfile?,
        visibleIssues: [CivicIssue],
        filings: [ChatFilingSnapshot],
        matchedServices: [CivicService]
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

struct ChatFilingSnapshot {
    let issueTitle: String
    let action: CivicAction
    let officialName: String
    let sentAt: Date
    let confirmationCode: String
}

struct HTTPChatService: ChatServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 60) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func stream(
        messages: [ChatMessage],
        profile: UserProfile?,
        visibleIssues: [CivicIssue],
        filings: [ChatFilingSnapshot],
        matchedServices: [CivicService]
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = ChatRequest(
                        messages: messages.map { ChatRequest.Message(role: $0.role.rawValue, content: $0.content) },
                        context: ChatRequest.Context(profile: profile.map(ChatRequest.Profile.init(from:)),
                                                    visibleIssues: visibleIssues.map { ChatRequest.Issue(from: $0, profile: profile) },
                                                    filingHistory: filings.map(ChatRequest.Filing.init(from:)),
                                                    matchedServices: matchedServices.map { ChatRequest.MatchedService(from: $0, profile: profile) })
                    )

                    var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat"), timeoutInterval: timeout)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw CivicFilingError.invalidResponse
                    }
                    if !(200..<300).contains(http.statusCode) {
                        var collected = Data()
                        for try await byte in bytes { collected.append(byte) }
                        let message = (try? JSONDecoder().decode(ChatErrorResponse.self, from: collected))?.error.message
                        throw CivicFilingError.server(status: http.statusCode, message: message ?? "Chat failed.")
                    }

                    var currentEvent = "message"
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.isEmpty {
                            currentEvent = "message"
                            continue
                        }
                        if line.hasPrefix("event:") {
                            currentEvent = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
                            continue
                        }
                        if line.hasPrefix("data:") {
                            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                            guard let data = payload.data(using: .utf8) else { continue }

                            switch currentEvent {
                            case "delta":
                                if let decoded = try? JSONDecoder().decode(DeltaPayload.self, from: data) {
                                    continuation.yield(.delta(decoded.text))
                                }
                            case "tool_start":
                                if let decoded = try? JSONDecoder().decode(ToolStartPayload.self, from: data) {
                                    continuation.yield(.toolStart(name: decoded.name))
                                }
                            case "tool_done":
                                if let decoded = try? JSONDecoder().decode(ToolDonePayload.self, from: data) {
                                    continuation.yield(.toolDone(name: decoded.name, summary: decoded.summary))
                                }
                            case "done":
                                continuation.yield(.done)
                            case "error":
                                if let decoded = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
                                    continuation.yield(.error(decoded.message))
                                }
                            default:
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct MockChatService: ChatServicing {
    func stream(
        messages: [ChatMessage],
        profile: UserProfile?,
        visibleIssues _: [CivicIssue],
        filings _: [ChatFilingSnapshot],
        matchedServices _: [CivicService]
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let response = Self.canned(for: messages.last?.content ?? "", profile: profile)
        return AsyncThrowingStream { continuation in
            Task {
                let chunks = response.split(separator: " ", omittingEmptySubsequences: false)
                for (i, chunk) in chunks.enumerated() {
                    if Task.isCancelled { continuation.finish(); return }
                    try? await Task.sleep(nanoseconds: 35_000_000)
                    let prefix = i == 0 ? "" : " "
                    continuation.yield(.delta(prefix + chunk))
                }
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    private static func canned(for prompt: String, profile: UserProfile?) -> String {
        let lower = prompt.lowercased()
        if profile == nil {
            return "Open Radar, tap the profile button, and enter your ZIP first — I use it to pull your federal, state, and local reps so I can point you at the right place. Once that's set, ask me anything: what's on this week, who to call, or how to rally friends to file."
        }
        if lower.contains("outreach") || lower.contains("campaign") || lower.contains("rally") {
            return "Here's a 4-step outreach plan you can run today:\n\n1. Pick the issue from Home or Feed. Open its detail and copy the title.\n2. Text 5 friends. Subject: \"Quick civic ask\". Body: \"Hey — there's a vote on [TITLE] this week. Takes 30s in \(AppBrand.name). Endorse or oppose, your call.\"\n3. Post one story with the same line plus a screenshot of the issue card.\n4. Tomorrow morning, message anyone who hasn't filed yet.\n\nWant me to draft the texts in your voice?"
        }
        if lower.contains("rep") || lower.contains("senator") || lower.contains("congress") {
            return "Your reps are in profile from the Radar tab — federal, state, and local grouped together. From any issue you can tap Endorse or Oppose and we'll file with the right one automatically."
        }
        return "I'm in mock mode right now, so I can only reason from the cards already in the app. Start with the top item in Your civic radar, check the Why this matters card, then file or save it. Wire CIVIC_API_BASE_URL to get live assistant reasoning."
    }
}

private struct ChatRequest: Encodable {
    let messages: [Message]
    let context: Context

    struct Message: Encodable { let role: String; let content: String }

    struct Context: Encodable {
        let profile: Profile?
        let visibleIssues: [Issue]
        let filingHistory: [Filing]
        let matchedServices: [MatchedService]
    }

    struct Profile: Encodable {
        let zipCode: String
        let stateCode: String
        let stateName: String
        let localityLabel: String?
        let factors: [String]
        let officials: Officials

        struct Officials: Encodable {
            let federalSenators: [OfficialEntry]
            let federalHouseRep: OfficialEntry?
            let stateSenators: [OfficialEntry]
            let stateRepresentatives: [OfficialEntry]
            let local: [OfficialEntry]
        }

        struct OfficialEntry: Encodable {
            let name: String
            let title: String
            let district: String?
        }

        init(from profile: UserProfile) {
            zipCode = profile.zipCode
            stateCode = profile.stateCode
            stateName = profile.stateName
            localityLabel = profile.localityLabel
            factors = profile.factors.sorted(by: { $0.label < $1.label }).map(\.label)
            officials = Officials(
                federalSenators: profile.officials.federalSenators.map(OfficialEntry.init(from:)),
                federalHouseRep: profile.officials.federalHouseRep.map(OfficialEntry.init(from:)),
                stateSenators: profile.officials.stateSenators.map(OfficialEntry.init(from:)),
                stateRepresentatives: profile.officials.stateRepresentatives.map(OfficialEntry.init(from:)),
                local: profile.officials.local.map(OfficialEntry.init(from:))
            )
        }
    }

    struct Issue: Encodable {
        let id: String
        let title: String
        let jurisdiction: String
        let scope: String
        let impactLevel: String
        let voteDateISO: String
        let summary: String
        let whyItMatters: String
        let recommendedAction: String
        let trustScore: Int
        let sourceName: String

        init(from issue: CivicIssue, profile: UserProfile?) {
            id = issue.id.uuidString
            title = issue.title
            jurisdiction = issue.jurisdiction
            scope = issue.scope.shortLabel
            impactLevel = issue.impactLevel.rawValue
            let formatter = ISO8601DateFormatter()
            voteDateISO = formatter.string(from: issue.voteDate)
            summary = issue.summary
            whyItMatters = issue.personalReason(for: profile)
            recommendedAction = issue.recommendedAction(alreadySent: false)
            trustScore = issue.trustScore
            sourceName = issue.sourceName
        }
    }

    struct Filing: Encodable {
        let issueTitle: String
        let action: String
        let officialName: String
        let sentAt: String
        let confirmationCode: String

        init(from snapshot: ChatFilingSnapshot) {
            issueTitle = snapshot.issueTitle
            action = snapshot.action == .endorse ? "endorse" : "oppose"
            officialName = snapshot.officialName
            sentAt = ISO8601DateFormatter().string(from: snapshot.sentAt)
            confirmationCode = snapshot.confirmationCode
        }
    }

    struct MatchedService: Encodable {
        let id: String
        let title: String
        let category: String
        let provider: String
        let summary: String
        let matchScore: Int
        let nextStep: String
        let missingDocuments: [String]
        let sourceName: String
        let sourceURL: String

        init(from service: CivicService, profile: UserProfile?) {
            id = service.id.uuidString
            title = service.title
            category = service.category.label
            provider = service.provider
            summary = service.summary
            matchScore = service.matchScore(for: profile)
            nextStep = service.applySteps.first ?? "Check the official source"
            let prepared = profile?.preparedDocuments ?? []
            missingDocuments = service.documents
                .filter { !prepared.contains($0) }
                .map(\.label)
            sourceName = service.sourceName
            sourceURL = service.sourceURL
        }
    }
}

private extension ChatRequest.Profile.OfficialEntry {
    init(from summary: OfficialSummary) {
        self.name = summary.name
        self.title = summary.title
        self.district = summary.district
    }
}

private struct DeltaPayload: Decodable { let text: String }
private struct ErrorPayload: Decodable { let message: String }
private struct ToolStartPayload: Decodable { let name: String }
private struct ToolDonePayload: Decodable { let name: String; let summary: String }
private struct ChatErrorResponse: Decodable {
    let error: ErrorBody
    struct ErrorBody: Decodable { let code: String; let message: String }
}
