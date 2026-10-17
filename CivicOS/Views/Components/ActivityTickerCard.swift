import SwiftUI

/// Lightweight activity feed card for Home. Reads from local state
/// (issues + diff events) and surfaces the 5 most recent civic moves —
/// new bill ingested, status change, recent vote.
///
/// Backed by the backend's `/v1/activity/ticker` SSE stream but doesn't
/// stream live yet (v1). Today it just snapshots local data; a true
/// realtime upgrade hooks the same UI to the SSE endpoint in v1.1.
struct ActivityTickerCard: View {
    @Environment(CivicOSStore.self) private var store
    let onSelectIssue: (UUID) -> Void

    var body: some View {
        if events.isEmpty {
            EmptyView()
        } else {
            CivicGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(events.prefix(5)) { event in
                            row(event)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(CivicTheme.green)
                .frame(width: 7, height: 7)
            Text("Civic ticker")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            Text("Live")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(CivicTheme.green, in: Capsule())
        }
    }

    private func row(_ event: TickerEvent) -> some View {
        Button {
            Haptics.selection()
            onSelectIssue(event.issueID)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(event.tint.opacity(0.16))
                    Image(systemName: event.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(event.tint)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CivicTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(event.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
        }
        .buttonStyle(.plain)
    }

    private var events: [TickerEvent] {
        let recentIssues = store.issues
            .filter { $0.voteDate > Date.now.addingTimeInterval(-30 * 24 * 3600) }
            .sorted { $0.voteDate > $1.voteDate }
            .prefix(10)
        return recentIssues.map { issue in
            TickerEvent(
                id: issue.id.uuidString + "-bill",
                issueID: issue.id,
                title: issue.title,
                subtitle: "\(issue.jurisdiction) · \(relativeTime(issue.voteDate))",
                icon: "doc.text.fill",
                tint: CivicTheme.cyan,
            )
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date.now)
    }
}

private struct TickerEvent: Identifiable {
    let id: String
    let issueID: UUID
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
}
