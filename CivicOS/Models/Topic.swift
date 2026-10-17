import SwiftUI

enum CivicTopic: String, CaseIterable, Codable, Hashable, Identifiable {
    case housing
    case transit
    case education
    case environment
    case publicSafety
    case health
    case money

    var id: String { rawValue }

    var label: String {
        switch self {
        case .housing: "Housing"
        case .transit: "Transit"
        case .education: "Education"
        case .environment: "Environment"
        case .publicSafety: "Public Safety"
        case .health: "Health"
        case .money: "Taxes & Budget"
        }
    }

    var systemImage: String {
        switch self {
        case .housing: "house.fill"
        case .transit: "tram.fill"
        case .education: "graduationcap.fill"
        case .environment: "leaf.fill"
        case .publicSafety: "shield.fill"
        case .health: "cross.case.fill"
        case .money: "dollarsign.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .housing: CivicTheme.cyan
        case .transit: CivicTheme.violet
        case .education: CivicTheme.amber
        case .environment: CivicTheme.green
        case .publicSafety: CivicTheme.red
        case .health: CivicTheme.violet
        case .money: CivicTheme.amber
        }
    }
}
