import Foundation
import SwiftUI

/// Catalog of third-party services Athen can connect to via Composio. Surfaced
/// in the You tab so the user can opt in app-by-app. Currently scaffold: Gmail
/// is the only one wired into the filing dispatcher.
struct CivicIntegrationApp: Decodable, Equatable, Hashable, Identifiable {
    let appName: String
    let displayName: String
    let systemImage: String
    let description: String

    var id: String { appName }

    var tint: Color {
        switch appName {
        case "gmail": CivicTheme.red
        case "googlecalendar": CivicTheme.cyan
        case "slack": CivicTheme.violet
        case "notion": CivicTheme.ink
        default: CivicTheme.mutedInk
        }
    }
}

struct CivicIntegrationCatalog: Decodable, Equatable, Hashable {
    let enabled: Bool
    let apps: [CivicIntegrationApp]
}

struct CivicIntegrationStatus: Decodable, Equatable, Hashable, Identifiable {
    let appName: String
    let isConnected: Bool
    let connectionId: String?
    let status: String?

    var id: String { appName }
}

struct CivicIntegrationStatusList: Decodable, Equatable, Hashable {
    let enabled: Bool
    let items: [CivicIntegrationStatus]
}

struct CivicIntegrationConnectResult: Decodable, Equatable, Hashable {
    let connectionId: String
    let redirectUrl: String
    let status: String
}
