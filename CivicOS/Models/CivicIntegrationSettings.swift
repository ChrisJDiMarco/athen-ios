import Foundation

/// Per-automation user preferences. Persisted to UserDefaults so the next
/// launch picks up the user's choices. The actual integrations are gated by
/// connection state (in `integrationStatusByApp`) — these settings only
/// matter once the relevant app is connected.
struct CivicIntegrationSettings: Codable, Equatable, Hashable {
    // Calendar
    var calendarOnBookmark: Bool = false

    // Notion
    var notionOnFiling: Bool = false
    var notionOnPetition: Bool = false
    var notionDatabaseId: String = ""

    // Slack
    var slackOnGroupLetter: Bool = false
    var slackOnDailyBrief: Bool = false
    var slackChannel: String = ""

    // Discord
    var discordOnGroupLetter: Bool = false
    var discordOnPetition: Bool = false
    var discordChannelId: String = ""

    // Social (X / LinkedIn)
    var twitterOnFiling: Bool = false
    var linkedinOnFiling: Bool = false
    var socialHashtags: String = "civics athen"

    // Gmail (already wired separately for filings)
    var gmailDigestEnabled: Bool = false
    var gmailDigestRecipient: String = ""

    static let `default` = CivicIntegrationSettings()
}

extension CivicIntegrationSettings {
    /// All the automations the user has enabled and that are wired to an
    /// active connection. Used for the iOS settings panel summary count.
    func enabledAutomationCount(connectedApps: Set<String>) -> Int {
        var count = 0
        if calendarOnBookmark && connectedApps.contains("googlecalendar") { count += 1 }
        if notionOnFiling && connectedApps.contains("notion") && !notionDatabaseId.isEmpty { count += 1 }
        if notionOnPetition && connectedApps.contains("notion") && !notionDatabaseId.isEmpty { count += 1 }
        if slackOnGroupLetter && connectedApps.contains("slack") && !slackChannel.isEmpty { count += 1 }
        if slackOnDailyBrief && connectedApps.contains("slack") && !slackChannel.isEmpty { count += 1 }
        if discordOnGroupLetter && connectedApps.contains("discord") && !discordChannelId.isEmpty { count += 1 }
        if discordOnPetition && connectedApps.contains("discord") && !discordChannelId.isEmpty { count += 1 }
        if twitterOnFiling && connectedApps.contains("twitter") { count += 1 }
        if linkedinOnFiling && connectedApps.contains("linkedin") { count += 1 }
        if gmailDigestEnabled && connectedApps.contains("gmail") && !gmailDigestRecipient.isEmpty { count += 1 }
        return count
    }
}
