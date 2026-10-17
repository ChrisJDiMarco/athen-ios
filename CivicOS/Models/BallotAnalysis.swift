import Foundation
import SwiftUI

/// Result of running a ballot photo through OCR + Claude. One BallotItem per
/// race or measure detected on the ballot. Includes neutral "what yes / no
/// means" framing — never voting advice.
struct BallotAnalysis: Decodable, Equatable, Hashable {
    let generatedAt: Date
    let model: String
    let items: [BallotItem]
    let notice: String

    enum CodingKeys: String, CodingKey {
        case generatedAtISO, model, items, notice
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let iso = try c.decode(String.self, forKey: .generatedAtISO)
        self.generatedAt = ISO8601DateFormatter().date(from: iso) ?? .now
        self.model = try c.decode(String.self, forKey: .model)
        self.items = try c.decode([BallotItem].self, forKey: .items)
        self.notice = try c.decode(String.self, forKey: .notice)
    }

    init(generatedAt: Date, model: String, items: [BallotItem], notice: String) {
        self.generatedAt = generatedAt
        self.model = model
        self.items = items
        self.notice = notice
    }
}

struct BallotItem: Decodable, Equatable, Hashable, Identifiable {
    let rawText: String
    let itemTitle: String
    let itemKind: Kind
    let plainEnglish: String
    let whatYesMeans: String?
    let whatNoMeans: String?
    let considerations: [String]

    var id: String { itemTitle + "|" + rawText.prefix(80) }

    enum Kind: String, Decodable, Hashable {
        case candidate
        case measure
        case amendment
        case unknown

        var label: String {
            switch self {
            case .candidate: "Candidate"
            case .measure: "Measure"
            case .amendment: "Amendment"
            case .unknown: "Item"
            }
        }

        var systemImage: String {
            switch self {
            case .candidate: "person.text.rectangle.fill"
            case .measure: "checklist"
            case .amendment: "doc.badge.gearshape.fill"
            case .unknown: "questionmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .candidate: CivicTheme.cyan
            case .measure: CivicTheme.violet
            case .amendment: CivicTheme.amber
            case .unknown: CivicTheme.mutedInk
            }
        }
    }
}
