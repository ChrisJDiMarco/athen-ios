import Foundation
import UserNotifications

/// Schedules local notifications for upcoming votes/comment deadlines on
/// issues the user has bookmarked or that match their interests.
///
/// Two reminders per issue:
///   - T-24h: "Vote tomorrow on <title> · file before <local time>"
///   - T-1h:  "<title> votes in 1 hour. Hit Endorse or Oppose now."
///
/// All notifications are LOCAL — no APNS, no server push. They survive
/// reboot via UNUserNotificationCenter's persistence.
@MainActor
final class CivicNotificationScheduler {
    static let shared = CivicNotificationScheduler()
    private let center = UNUserNotificationCenter.current()

    private(set) var lastAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        lastAuthorizationStatus = settings.authorizationStatus
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .providesAppNotificationSettings])
                let updated = await center.notificationSettings()
                lastAuthorizationStatus = updated.authorizationStatus
                return granted
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    /// Recompute all pending civic reminders to match the current set of
    /// (bookmarked OR interest-matched) issues with upcoming vote dates.
    /// Safe to call repeatedly; existing reminders are cleared and rewritten.
    func reschedule(for issues: [CivicIssue], bookmarked: Set<CivicIssue.ID>, interests: Set<CivicTopic>) async {
        guard await requestAuthorizationIfNeeded() else {
            await center.removeAllPendingNotificationRequests()
            return
        }

        let now = Date.now
        let upcoming = issues.filter { issue in
            guard issue.voteDate > now else { return false }
            if bookmarked.contains(issue.id) { return true }
            if interests.isEmpty { return false }
            return !issue.topics.isDisjoint(with: interests)
        }

        // Wipe and re-add — simpler and correct than diffing.
        let existing = await center.pendingNotificationRequests()
        let civicIDs = existing.map(\.identifier).filter { $0.hasPrefix("athen.deadline.") }
        center.removePendingNotificationRequests(withIdentifiers: civicIDs)

        for issue in upcoming.prefix(50) {
            for offset in [24.0 * 3600.0, 1.0 * 3600.0] {
                let fireDate = issue.voteDate.addingTimeInterval(-offset)
                guard fireDate > now else { continue }
                let content = UNMutableNotificationContent()
                if offset >= 23 * 3600 {
                    content.title = "Vote tomorrow on this civic item"
                    content.body = "\(issue.title) — \(formattedTime(issue.voteDate))"
                } else {
                    content.title = "Vote in about an hour"
                    content.body = "\(issue.title). Open Athen to endorse or oppose."
                }
                content.sound = .default
                content.userInfo = [
                    "issueID": issue.id.uuidString,
                    "kind": "deadline",
                ]
                content.threadIdentifier = "athen.deadline.\(issue.id.uuidString)"
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                    repeats: false
                )
                let id = "athen.deadline.\(issue.id.uuidString).\(Int(offset))"
                let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                do { try await center.add(req) } catch {
                    // Fail quietly — scheduling is best-effort.
                }
            }
        }
    }

    func currentPendingCount() async -> Int {
        await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("athen.deadline.") }.count
    }

    /// Schedules a "you're about to break your civic streak" notification
    /// that fires at 8pm if the user hasn't opened Athen today. Reschedule
    /// on every app open. Best-effort: noisy if granted, silent if not.
    func scheduleStreakInsurance(currentStreakDays: Int) async {
        guard currentStreakDays > 0 else { return }
        guard await requestAuthorizationIfNeeded() else { return }

        // Clear any prior streak reminder so we don't double-fire.
        let existing = await center.pendingNotificationRequests()
        let streakIDs = existing.map(\.identifier).filter { $0.hasPrefix("athen.streak.") }
        center.removePendingNotificationRequests(withIdentifiers: streakIDs)

        let content = UNMutableNotificationContent()
        content.title = "Don't break your civic streak"
        let dayLabel = currentStreakDays == 1 ? "day" : "days"
        content.body = "You're on day \(currentStreakDays). Pop in for 60 seconds to keep \(dayLabel) the streak alive."
        content.sound = .default
        content.userInfo = ["kind": "streak"]
        content.threadIdentifier = "athen.streak"

        // Fire today at 8pm local. If 8pm has passed, schedule for tomorrow.
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = 20
        components.minute = 0
        let target = Calendar.current.date(from: components) ?? .now
        let fireDate = target > .now ? target : target.addingTimeInterval(24 * 3600)

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
            repeats: false
        )
        let req = UNNotificationRequest(identifier: "athen.streak.\(fireDate.timeIntervalSince1970)", content: content, trigger: trigger)
        try? await center.add(req)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
