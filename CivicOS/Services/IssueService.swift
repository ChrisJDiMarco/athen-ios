import Foundation

protocol IssueServicing {
    func fetchIssues(for profile: UserProfile?) async throws -> IssueRefreshResult
}

protocol AthenBriefServicing {
    func fetchBriefPosts(for profile: UserProfile?) async throws -> [SocialPost]
}

struct IssueRefreshResult {
    let issues: [CivicIssue]
    let brief: CivicBrief?
}

struct CivicBrief: Equatable, Hashable {
    let generatedAtISO: String
    let locationLabel: String
    let headline: String
    let summary: String
    let metrics: Metrics
    let sourceHealth: SourceHealth
    let actions: [Action]

    struct Metrics: Equatable, Hashable, Decodable {
        let activeIssues: Int
        let urgentIssues: Int
        let serviceMatches: Int
        let averageTrustScore: Int?
    }

    struct SourceHealth: Equatable, Hashable, Decodable {
        let registeredSources: Int?
        let activeSourceHosts: Int
        let lastUpdatedAt: String?
        let freshnessLabel: String
        let averageTrustScore: Int?
    }

    struct Action: Identifiable, Equatable, Hashable, Decodable {
        let id: String
        let kind: String
        let priority: Int
        let title: String
        let detail: String
        let cta: String
        let systemImage: String
        let issueID: UUID?
        let serviceID: UUID?

        enum CodingKeys: String, CodingKey {
            case id
            case kind
            case priority
            case title
            case detail
            case cta
            case systemImage
            case issueID
            case serviceID
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            kind = try container.decode(String.self, forKey: .kind)
            priority = try container.decode(Int.self, forKey: .priority)
            title = try container.decode(String.self, forKey: .title)
            detail = try container.decode(String.self, forKey: .detail)
            cta = try container.decode(String.self, forKey: .cta)
            systemImage = try container.decode(String.self, forKey: .systemImage)
            issueID = try container.decodeIfPresent(String.self, forKey: .issueID).flatMap(UUID.init(uuidString:))
            serviceID = try container.decodeIfPresent(String.self, forKey: .serviceID).flatMap(UUID.init(uuidString:))
        }
    }
}

struct HTTPIssueService: IssueServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 15) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func fetchIssues(for profile: UserProfile?) async throws -> IssueRefreshResult {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/issues"), resolvingAgainstBaseURL: false)!
        var query: [URLQueryItem] = []
        if let profile {
            query.append(URLQueryItem(name: "stateCode", value: profile.stateCode))
            query.append(URLQueryItem(name: "zip", value: profile.zipCode))
            if !profile.serviceNeeds.isEmpty {
                query.append(URLQueryItem(name: "needs", value: profile.serviceNeeds.map(\.rawValue).sorted().joined(separator: ",")))
            }
            if !profile.eligibilitySignals.isEmpty {
                query.append(URLQueryItem(name: "signals", value: profile.eligibilitySignals.map(\.rawValue).sorted().joined(separator: ",")))
            }
            if !profile.preparedDocuments.isEmpty {
                query.append(URLQueryItem(name: "documents", value: profile.preparedDocuments.map(\.rawValue).sorted().joined(separator: ",")))
            }
            query.append(URLQueryItem(name: "language", value: profile.preferredLanguage.rawValue))
        }
        components.queryItems = query.isEmpty ? nil : query

        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CivicFilingError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(IssueErrorResponse.self, from: data))?.error.message
            throw CivicFilingError.server(status: http.statusCode, message: message ?? "Could not load issues.")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(IssuesResponse.self, from: data)
        return IssueRefreshResult(issues: payload.issues.compactMap(\.toCivicIssue), brief: payload.brief?.toCivicBrief)
    }
}

struct MockIssueService: IssueServicing {
    func fetchIssues(for _: UserProfile?) async throws -> IssueRefreshResult {
        return IssueRefreshResult(issues: [], brief: nil)
    }
}

struct HTTPAthenBriefService: AthenBriefServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 15) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func fetchBriefPosts(for profile: UserProfile?) async throws -> [SocialPost] {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/briefs"), resolvingAgainstBaseURL: false)!
        var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: "12")]
        if let profile {
            query.append(URLQueryItem(name: "stateCode", value: profile.stateCode))
            query.append(URLQueryItem(name: "zip", value: profile.zipCode))
        }
        components.queryItems = query

        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }
        let payload = try JSONDecoder.athenISO.decode(BriefsResponse.self, from: data)
        return payload.briefs.map(\.toSocialPost)
    }
}

struct MockAthenBriefService: AthenBriefServicing {
    func fetchBriefPosts(for _: UserProfile?) async throws -> [SocialPost] { [] }
}

private struct IssuesResponse: Decodable {
    let issues: [IssueDTO]
    let brief: BriefDTO?
}

private struct IssueErrorResponse: Decodable {
    let error: ErrorBody
    struct ErrorBody: Decodable { let message: String }
}

private struct BriefsResponse: Decodable {
    let briefs: [FeedBriefDTO]
}

private struct FeedBriefDTO: Decodable {
    let issueID: String?
    let authorName: String
    let authorHandle: String
    let authorEmoji: String
    let body: String
    let locality: String
    let createdAtISO: Date
    let issueTitle: String
    let explainer: ExplainerDTO

    struct ExplainerDTO: Decodable {
        let headline: String
        let plainEnglish: String
        let stakes: String
        let positions: [PositionDTO]
        let nextStep: String
        let visualPrompt: String
        let sourceLine: String
        let confidenceLabel: String
    }

    struct PositionDTO: Decodable {
        let kind: String
        let title: String
        let summary: String
    }

    var toSocialPost: SocialPost {
        SocialPost(
            authorName: authorName,
            authorHandle: authorHandle,
            authorEmoji: authorEmoji,
            body: body,
            kind: .aiBrief,
            issueID: issueID.flatMap(UUID.init(uuidString:)),
            issueTitle: issueTitle,
            locality: locality,
            explainer: AIExplainer(
                headline: explainer.headline,
                plainEnglish: explainer.plainEnglish,
                stakes: explainer.stakes,
                positions: explainer.positions.map {
                    ExplainerPosition(
                        kind: ExplainerPositionKind(rawValue: $0.kind) ?? .watch,
                        title: $0.title,
                        summary: $0.summary
                    )
                },
                nextStep: explainer.nextStep,
                visualPrompt: explainer.visualPrompt,
                sourceLine: explainer.sourceLine,
                confidenceLabel: explainer.confidenceLabel
            ),
            createdAt: createdAtISO,
            likeCount: 0,
            commentCount: 0,
            shareCount: 0
        )
    }
}

private struct BriefDTO: Decodable {
    let generatedAtISO: String
    let locationLabel: String
    let headline: String
    let summary: String
    let metrics: CivicBrief.Metrics
    let sourceHealth: CivicBrief.SourceHealth
    let actions: [CivicBrief.Action]

    var toCivicBrief: CivicBrief {
        CivicBrief(
            generatedAtISO: generatedAtISO,
            locationLabel: locationLabel,
            headline: headline,
            summary: summary,
            metrics: metrics,
            sourceHealth: sourceHealth,
            actions: actions
        )
    }
}

private struct IssueDTO: Decodable {
    let id: String
    let title: String
    let category: String
    let jurisdiction: String
    let scope: String
    let stateCode: String?
    let zipCode: String?
    let summary: String
    let impactLevel: String
    let voteDateISO: String
    let sourceName: String
    let sourceDetail: String
    let sourceURL: String?
    let sourceHost: String?
    let sourceType: String?
    let trustScore: Int?
    let extractionConfidence: Double?
    let citations: [CitationDTO]?
    let topics: [String]
    let facts: [FactDTO]
    let official: OfficialDTO
    let filingRoute: RouteDTO
    let reply: ReplyDTO?

    struct FactDTO: Decodable {
        let label: String
        let value: String
        let systemImage: String?
    }

    struct CitationDTO: Decodable {
        let label: String
        let quote: String
        let url: String?
    }

    struct OfficialDTO: Decodable {
        let name: String
        let title: String
        let district: String
        let contactTarget: String
    }

    struct RouteDTO: Decodable {
        let verificationStep: String
        let routingStep: String
        let destinationStep: String
        let deliveryWindow: String
    }

    struct ReplyDTO: Decodable {
        let receivedAt: Date
        let summary: String
        let stance: String
    }

    var toCivicIssue: CivicIssue? {
        guard let id = UUID(uuidString: id) else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let voteDate = isoFormatter.date(from: voteDateISO)
            ?? ISO8601DateFormatter().date(from: voteDateISO)
            ?? .now

        let scopeValue: JurisdictionScope
        switch scope {
        case "federal": scopeValue = .federal
        case "local-philly": scopeValue = .localPhilly
        default:
            if let state = stateCode { scopeValue = .state(state) } else { scopeValue = .federal }
        }

        let impact: ImpactLevel
        switch impactLevel {
        case "urgent", "High Impact": impact = .urgent
        case "watch", "Watch": impact = .watch
        default: impact = .material
        }

        let topicValues = Set(topics.compactMap { CivicTopic(rawValue: $0) })

        return CivicIssue(
            id: id,
            title: title,
            category: category,
            jurisdiction: jurisdiction,
            scope: scopeValue,
            zipCode: zipCode ?? "",
            summary: summary,
            impactLevel: impact,
            voteDate: voteDate,
            sourceName: sourceName,
            sourceDetail: sourceDetail,
            sourceURL: sourceURL,
            facts: facts.map { TranslationFact(label: $0.label, value: $0.value, systemImage: $0.systemImage ?? "doc.text") },
            official: LocalOfficial(
                id: UUID(),
                name: official.name,
                title: official.title,
                district: official.district,
                contactTarget: official.contactTarget
            ),
            filingRoute: FilingRoute(
                verificationStep: filingRoute.verificationStep,
                routingStep: filingRoute.routingStep,
                destinationStep: filingRoute.destinationStep,
                deliveryWindow: filingRoute.deliveryWindow
            ),
            reply: reply.map {
                OfficialReply(id: UUID(), receivedAt: $0.receivedAt, summary: $0.summary, stance: $0.stance)
            },
            topics: topicValues,
            trustScoreOverride: trustScore,
            extractionConfidence: extractionConfidence,
            sourceHost: sourceHost,
            sourceType: sourceType,
            citations: (citations ?? []).map {
                IssueCitation(label: $0.label, quote: $0.quote, url: $0.url)
            }
        )
    }
}

private extension JSONDecoder {
    static var athenISO: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }
            if let date = ISO8601DateFormatter().date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(raw)")
        }
        return decoder
    }
}
