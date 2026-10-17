import Foundation

struct BackgroundReading: Equatable, Hashable, Codable {
    let summary: String
    let citations: [BackgroundCitation]
    let generatedAt: Date

    var hasContent: Bool {
        !summary.isEmpty && !citations.isEmpty
    }
}

struct BackgroundCitation: Equatable, Hashable, Codable, Identifiable {
    var id: String { url }

    let source: String
    let title: String
    let url: String
    let snippet: String
}
