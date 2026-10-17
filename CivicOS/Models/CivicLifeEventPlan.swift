import Foundation
import SwiftUI

/// Plain-English civic plan generated from a life-event description.
/// Persisted locally so users can return to past plans (e.g., a layoff plan
/// they keep coming back to as steps complete). Codable for UserDefaults.
struct CivicLifeEventPlan: Codable, Equatable, Hashable, Identifiable {
    /// Stable per-plan id assigned client-side at create time.
    let id: String
    let generatedAtISO: String
    let situation: String
    let category: String
    let immediateSteps: [PlanStep]
    let nearTermSteps: [PlanStep]
    let longerTermSteps: [PlanStep]
    let qualifyingPrograms: [QualifyingProgram]
    let civicAsks: [CivicAsk]
    let notes: [String]
    /// User-original input — useful for "regenerate" or display in history.
    let originalDescription: String

    var generatedAt: Date {
        ISO8601DateFormatter().date(from: generatedAtISO) ?? .now
    }

    var totalSteps: Int {
        immediateSteps.count + nearTermSteps.count + longerTermSteps.count
    }
}

struct PlanStep: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let title: String
    let description: String
    let urgency: Urgency
    let action: Action

    enum Urgency: String, Codable, Hashable {
        case today, thisWeek = "this-week", thisMonth = "this-month", ongoing

        var label: String {
            switch self {
            case .today: "Today"
            case .thisWeek: "This week"
            case .thisMonth: "This month"
            case .ongoing: "Ongoing"
            }
        }

        var tint: Color {
            switch self {
            case .today: CivicTheme.red
            case .thisWeek: CivicTheme.amber
            case .thisMonth: CivicTheme.cyan
            case .ongoing: CivicTheme.violet
            }
        }
    }

    struct Action: Codable, Equatable, Hashable {
        let kind: Kind
        let url: String?
        let phone: String?
        let calendarTitle: String?
        let calendarDateISO: String?
        let label: String?

        enum Kind: String, Codable, Hashable {
            case url, phone, calendar
            case fileIssue = "file-issue"
            case service
            case petition
            case manual

            var systemImage: String {
                switch self {
                case .url: "arrow.up.right.square"
                case .phone: "phone.fill"
                case .calendar: "calendar.badge.plus"
                case .fileIssue: "envelope.fill"
                case .service: "heart.text.square.fill"
                case .petition: "person.3.sequence.fill"
                case .manual: "checkmark.circle"
                }
            }

            var label: String {
                switch self {
                case .url: "Open"
                case .phone: "Call"
                case .calendar: "Add to calendar"
                case .fileIssue: "File"
                case .service: "View service"
                case .petition: "Sign petition"
                case .manual: "Mark done"
                }
            }
        }
    }
}

struct QualifyingProgram: Codable, Equatable, Hashable, Identifiable {
    let name: String
    let agency: String
    let eligibility: String
    let benefits: String
    let applyURL: String?
    let notes: String?

    var id: String { name + agency }
}

struct CivicAsk: Codable, Equatable, Hashable, Identifiable {
    let title: String
    let description: String
    let scope: Scope
    let why: String

    var id: String { title + scope.rawValue }

    enum Scope: String, Codable, Hashable {
        case federal, state, local, unknown
        var label: String { rawValue.capitalized }
        var tint: Color {
            switch self {
            case .federal: CivicTheme.cyan
            case .state: CivicTheme.violet
            case .local: CivicTheme.amber
            case .unknown: CivicTheme.mutedInk
            }
        }
    }
}

struct LifeEventPlanResponse: Decodable {
    /// Backend returns `{ plan: {…} }`. We strip the wrapper and stamp an
    /// `id` + `originalDescription` client-side before persisting.
    let plan: PlanPayload

    struct PlanPayload: Decodable {
        let generatedAtISO: String
        let situation: String
        let category: String
        let immediateSteps: [PlanStep]
        let nearTermSteps: [PlanStep]
        let longerTermSteps: [PlanStep]
        let qualifyingPrograms: [QualifyingProgram]
        let civicAsks: [CivicAsk]
        let notes: [String]
    }
}
