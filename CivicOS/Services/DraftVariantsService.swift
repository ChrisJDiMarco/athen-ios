import Foundation
import SwiftUI

struct DraftToneVariant: Identifiable, Equatable, Hashable, Decodable {
    let key: String
    let label: String
    let description: String
    let subject: String
    let body: String

    var id: String { key }

    var tint: Color {
        switch key {
        case "concerned": CivicTheme.cyan
        case "businessOwner": CivicTheme.amber
        case "parent": CivicTheme.green
        case "renter": CivicTheme.violet
        case "professional": CivicTheme.ink
        default: CivicTheme.mutedInk
        }
    }

    var systemImage: String {
        switch key {
        case "concerned": "person.fill"
        case "businessOwner": "briefcase.fill"
        case "parent": "figure.and.child.holdinghands"
        case "renter": "key.fill"
        case "professional": "graduationcap.fill"
        default: "person.fill"
        }
    }
}

protocol DraftVariantsServicing {
    func fetchVariants(action: CivicAction, issue: CivicIssue, zip: String, stateCode: String?, locality: String?) async throws -> [DraftToneVariant]
}

struct HTTPDraftVariantsService: DraftVariantsServicing {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL, session: URLSession = AthenURLSession.shared, timeout: TimeInterval = 90) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func fetchVariants(action: CivicAction, issue: CivicIssue, zip: String, stateCode: String?, locality: String?) async throws -> [DraftToneVariant] {
        let url = baseURL.appendingPathComponent("v1/file/variants")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let formatter = ISO8601DateFormatter()
        let body = RequestBody(
            action: action == .endorse ? "endorse" : "oppose",
            zip: zip,
            stateCode: stateCode,
            localityLabel: locality,
            issue: .init(
                id: issue.id.uuidString,
                title: issue.title,
                jurisdiction: issue.jurisdiction,
                sourceName: issue.sourceName,
                summary: issue.summary,
                facts: issue.facts.map { .init(label: $0.label, value: $0.value) },
                voteDateISO: formatter.string(from: issue.voteDate)
            )
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(VariantErrorResponse.self, from: data))?.error.message
            throw CivicFilingError.server(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: msg ?? "Variants request failed.")
        }
        let decoded = try JSONDecoder().decode(VariantsResponse.self, from: data)
        return decoded.variants
    }
}

struct MockDraftVariantsService: DraftVariantsServicing {
    func fetchVariants(action _: CivicAction, issue _: CivicIssue, zip _: String, stateCode _: String?, locality _: String?) async throws -> [DraftToneVariant] {
        []
    }
}

private struct RequestBody: Encodable {
    let action: String
    let zip: String
    let stateCode: String?
    let localityLabel: String?
    let issue: IssueBody

    struct IssueBody: Encodable {
        let id: String
        let title: String
        let jurisdiction: String
        let sourceName: String
        let summary: String
        let facts: [Fact]
        let voteDateISO: String

        struct Fact: Encodable { let label: String; let value: String }
    }
}

private struct VariantsResponse: Decodable { let variants: [DraftToneVariant] }

private struct VariantErrorResponse: Decodable {
    let error: ErrorBody
    struct ErrorBody: Decodable { let code: String; let message: String }
}
