import SwiftUI

struct BookmarksView: View {
    @Environment(CivicOSStore.self) private var store
    @State private var showCompareSheet = false

    var body: some View {
        ZStack {
            CivicTheme.screenBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if store.bookmarkedIssues.count >= 2 {
                        compareButton
                    }
                    if store.bookmarkedIssues.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.bookmarkedIssues) { issue in
                            NavigationLink(value: issue.id) {
                                BookmarkRow(issue: issue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: CivicIssue.ID.self) { id in
            if let issue = store.issue(with: id) {
                IssueDetailView(issue: issue)
            }
        }
        .sheet(isPresented: $showCompareSheet) {
            BillCompareSheet()
                .environment(store)
        }
    }

    private var compareButton: some View {
        Button {
            Haptics.selection()
            showCompareSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.split.2x1.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("Compare any two")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(CivicTheme.violet)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(CivicTheme.violet.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.violet.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Saved")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Items you've bookmarked. Athen tracks each one through committee, floor vote, and final signature.")
                .font(.system(size: 14))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if !store.bookmarkedIssues.isEmpty {
                stageBreakdown
                    .padding(.top, 4)
            }
        }
    }

    private var stageBreakdown: some View {
        let counts = stageCounts
        return HStack(spacing: 8) {
            stagePill(label: "Upcoming", count: counts.upcoming, tint: CivicTheme.cyan)
            stagePill(label: "Due soon", count: counts.dueSoon, tint: CivicTheme.amber)
            stagePill(label: "Voted", count: counts.voted, tint: CivicTheme.green)
        }
    }

    private struct StageCounts {
        var upcoming: Int = 0
        var dueSoon: Int = 0
        var voted: Int = 0
    }

    private var stageCounts: StageCounts {
        var c = StageCounts()
        for issue in store.bookmarkedIssues {
            if issue.hasVotePassed { c.voted += 1 }
            else if issue.hoursUntilVote <= 7 * 24 { c.dueSoon += 1 }
            else { c.upcoming += 1 }
        }
        return c
    }

    private func stagePill(label: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(count == 0 ? CivicTheme.quietInk : tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((count == 0 ? CivicTheme.hairline : tint).opacity(0.15), in: Capsule())
    }

    private var emptyState: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("No saved items yet", systemImage: "bookmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.violet)
                Text("Tap the bookmark icon on any issue to save it here. Useful for items you want to revisit before the vote.")
                    .font(.system(size: 14))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
            }
        }
    }
}

private struct BookmarkRow: View {
    let issue: CivicIssue

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    RectBadge(
                        text: issue.voteCountdownLabel,
                        systemImage: "calendar.badge.clock",
                        tint: CivicTheme.impactColor(for: issue.urgencyTint)
                    )
                    Spacer()
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(CivicTheme.violet)
                }
                Text(issue.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(issue.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineLimit(2)
            }
        }
    }
}
