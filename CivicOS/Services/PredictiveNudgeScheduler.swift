import Foundation
import UserNotifications

/// Schedules local notifications for upcoming votes on the user's bookmarked
/// issues. Runs on app foreground; no backend or APNs required. Each issue
/// gets at most one nudge per 24h, fired ~6 hours before the vote.
///
/// Why local instead of APNs: works offline, no Apple Developer push key,
/// no device-token plumbing. Apple lets us schedule notifications up to
/// 64 pending requests per app — plenty for civic deadlines.
@MainActor
final class PredictiveNudgeScheduler {
    static let shared = PredictiveNudgeScheduler()

    private let center = UNUserNotificationCenter.current()
    private let prefix = "athen.nudge.vote."
    /// "How far ahead of the vote should we ping?" — 6 hours gives the
    /// user time to act without being a same-second alarm.
    private let leadHours: Double = 6

    /// Re-syncs scheduled nudges against the current bookmarked issues.
    /// Idempotent — safe to call on every foreground.
    func sync(bookmarkedIssues: [CivicIssue]) async {
        let granted = await ensureAuthorization()
        guard granted else { return }

        // Snapshot existing pending nudges so we can prune stale ones.
        let existing = await center.pendingNotificationRequests()
        let existingNudgeIds = Set(
            existing
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
        )

        var keepIds: Set<String> = []
        for issue in bookmarkedIssues {
            // Only schedule for issues with a vote date in the future, and
            // at least 1h out (no point in pinging for something already done).
            let voteTime = issue.voteDate.timeIntervalSinceNow
            guard voteTime > 3600 else { continue }
            let identifier = nudgeId(for: issue)
            keepIds.insert(identifier)
            if existingNudgeIds.contains(identifier) {
                continue // already scheduled
            }
            let fireDate = issue.voteDate.addingTimeInterval(-leadHours * 3600)
            // If we're already past the ideal fire date (vote is <6h away),
            // schedule for "in 60 seconds" so the user gets pinged ASAP.
            let when = max(fireDate, Date.now.addingTimeInterval(60))
            scheduleNudge(for: issue, at: when, identifier: identifier)
        }

        // Cancel pending nudges for issues no longer bookmarked or whose
        // vote dates moved into the past since last sync.
        let toRemove = existingNudgeIds.subtracting(keepIds)
        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(toRemove))
        }
    }

    private func nudgeId(for issue: CivicIssue) -> String {
        prefix + issue.id.uuidString
    }

    private func scheduleNudge(for issue: CivicIssue, at when: Date, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = nudgeTitle(for: issue)
        content.body = nudgeBody(for: issue)
        content.sound = .default
        content.userInfo = ["issueId": issue.id.uuidString, "kind": "vote-nudge"]

        let interval = max(60, when.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { _ in
            // Errors here are usually transient (quota, OS load) — silently
            // skip; we'll re-sync on next foreground.
        }
    }

    private func nudgeTitle(for issue: CivicIssue) -> String {
        let countdown = issue.voteCountdownLabel
        return "\(countdown): \(shortTitle(issue.title))"
    }

    private func nudgeBody(for issue: CivicIssue) -> String {
        let who = issue.official.name.isEmpty ? "your rep" : issue.official.name
        return "Tap to review the brief and message \(who) before the vote."
    }

    /// Truncate long bill titles so the notification preview stays readable.
    private func shortTitle(_ title: String) -> String {
        if title.count <= 60 { return title }
        return String(title.prefix(58)) + "…"
    }

    private func ensureAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}
