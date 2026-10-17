import SwiftUI

/// Tiny three-chip header that gives the user signal density without the
/// wall-of-cards feeling. Each chip taps somewhere meaningful so it doubles
/// as navigation. Replaces the older "glance" metric block (items / next
/// vote / filed) which mixed lifetime stats with state and felt static.
struct HomePulseStrip: View {
    @Environment(CivicOSStore.self) private var store
    let onOpenStreak: () -> Void
    let onOpenChanges: () -> Void
    let onOpenNextDeadline: () -> Void

    private var nextDeadline: CivicIssue? {
        store.visibleIssues
            .filter { $0.voteDate > .now }
            .sorted { $0.voteDate < $1.voteDate }
            .first
    }

    private var deadlineLabel: String {
        guard let next = nextDeadline else { return "—" }
        let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: next.voteDate).day ?? 0)
        switch days {
        case 0: return "TODAY"
        case 1: return "1 day"
        case 2...6: return "\(days) days"
        case 7...30: return "\(days)d"
        default: return "\(days / 7)w"
        }
    }

    private var deadlineTint: Color {
        guard let next = nextDeadline else { return CivicTheme.quietInk }
        let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: next.voteDate).day ?? 0)
        switch days {
        case 0...2: return CivicTheme.red
        case 3...7: return CivicTheme.amber
        default: return CivicTheme.cyan
        }
    }

    private var diffCount: Int {
        store.diffEvents.count
    }

    var body: some View {
        HStack(spacing: 8) {
            streakChip
            diffChip
            deadlineChip
        }
    }

    private var streakChip: some View {
        Button(action: onOpenStreak) {
            chipContent(
                value: "\(store.civicStreakDays)d",
                label: store.civicStreakDays == 0 ? "Streak" : "On a streak",
                systemImage: store.civicStreakDays >= 7 ? "flame.fill" : "calendar.badge.checkmark",
                tint: store.civicStreakDays >= 7 ? CivicTheme.red : CivicTheme.cyan,
                emphasis: store.civicStreakDays >= 3
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Civic streak \(store.civicStreakDays) days")
    }

    @ViewBuilder
    private var diffChip: some View {
        if diffCount > 0 {
            Button(action: onOpenChanges) {
                chipContent(
                    value: "\(diffCount)",
                    label: diffCount == 1 ? "Change" : "Changes",
                    systemImage: "sparkles",
                    tint: CivicTheme.violet,
                    emphasis: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(diffCount) changes on bookmarked items")
        } else {
            chipContent(
                value: "0",
                label: "Quiet",
                systemImage: "checkmark.circle",
                tint: CivicTheme.quietInk,
                emphasis: false
            )
        }
    }

    @ViewBuilder
    private var deadlineChip: some View {
        if nextDeadline != nil {
            Button(action: onOpenNextDeadline) {
                chipContent(
                    value: deadlineLabel,
                    label: "Next vote",
                    systemImage: "clock.fill",
                    tint: deadlineTint,
                    emphasis: deadlineTint == CivicTheme.red || deadlineTint == CivicTheme.amber
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next vote \(deadlineLabel)")
        } else {
            chipContent(
                value: "—",
                label: "No deadline",
                systemImage: "clock",
                tint: CivicTheme.quietInk,
                emphasis: false
            )
        }
    }

    private func chipContent(value: String, label: String, systemImage: String, tint: Color, emphasis: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(emphasis ? tint : CivicTheme.ink)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(CivicTheme.quietInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(emphasis ? tint.opacity(0.10) : CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(emphasis ? tint.opacity(0.30) : CivicTheme.hairline, lineWidth: 1))
    }
}
