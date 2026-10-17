import Foundation

/// In-app notification entry — separate from the OS notification system so
/// the user can review what we've pinged them about even if they swiped
/// the system alert away or didn't have permissions granted.
///
/// Sources today:
///   - Vote deadline reminders (24h/1h before a bookmarked or interest-matched bill)
///   - Civic streak insurance (8pm same-day if streak risk)
///   - Filing receipts (when sent + when delivery confirmed)
///   - Petition delivery confirmations
struct AthenInboxNotification: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case deadline
        case streak
        case filingSent
        case petitionDelivered
        case systemUpdate
    }

    let id: String
    let kind: Kind
    let title: String
    let body: String
    /// Optional deep link target — usually a bill UUID.
    let issueID: UUID?
    let scheduledAtISO: String
    var isRead: Bool

    var scheduledAt: Date? {
        ISO8601DateFormatter().date(from: scheduledAtISO)
    }
}
