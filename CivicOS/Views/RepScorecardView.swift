import SwiftUI

/// Closes the loop on filings: shows the user how their reps actually voted
/// on the bills they took positions on. v1 mostly shows the relationship
/// (filing volume, topic mix, pending votes); alignment % populates as the
/// backend ingests roll-call data.
struct RepScorecardView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        intro
                        if isLoading && store.repScorecard == nil {
                            loadingCard
                        } else if let scorecards = store.repScorecard?.scorecards, !scorecards.isEmpty {
                            ForEach(scorecards) { card in
                                scorecardCard(card)
                            }
                            fineprint
                        } else {
                            emptyState
                        }
                        Color.clear.frame(height: 30)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
                .refreshable {
                    isLoading = true
                    await store.loadRepScorecard()
                    isLoading = false
                }
            }
            .navigationTitle("Rep scorecard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
            .task {
                if store.repScorecard == nil {
                    isLoading = true
                    await store.loadRepScorecard()
                    isLoading = false
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("REP SCORECARD", systemImage: "chart.bar.xaxis")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(CivicTheme.green)
            Text("How well do they represent you?")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("For every position you've filed, we compare your stance to your rep's actual vote (when the vote happens). Pending items appear immediately; alignment percentage fills in over time.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scorecardCard(_ card: RepScorecard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(CivicTheme.green.opacity(0.15))
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CivicTheme.green)
                }
                .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.officialName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                        .lineLimit(2)
                    Text("\(card.totalFilings) filing\(card.totalFilings == 1 ? "" : "s") · \(card.endorseCount) endorse · \(card.opposeCount) oppose")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                }
                Spacer()
                if let pct = card.alignmentPct {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(pct)%")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(alignmentTint(pct))
                            .monospacedDigit()
                        Text("ALIGNED")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(CivicTheme.quietInk)
                    }
                } else {
                    Text("Pending")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CivicTheme.amber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(CivicTheme.amber.opacity(0.12), in: Capsule())
                }
            }
            if !card.topicBreakdown.isEmpty {
                topicBreakdown(card.topicBreakdown)
            }
            if !card.mismatches.isEmpty {
                mismatchesSection(card.mismatches)
            }
            if !card.pending.isEmpty {
                pendingSection(card.pending)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.hairline, lineWidth: 1))
        .shadow(color: CivicTheme.cardShadow, radius: 8, x: 0, y: 3)
    }

    private func topicBreakdown(_ topics: [RepScorecard.TopicCount]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOPICS YOU'VE FILED ON")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(CivicTheme.quietInk)
            FlowLayout(spacing: 6) {
                ForEach(topics) { topic in
                    HStack(spacing: 4) {
                        Text(topic.topic.capitalized)
                            .font(.system(size: 11, weight: .bold))
                        Text("\(topic.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(CivicTheme.green, in: Capsule())
                    }
                    .foregroundStyle(CivicTheme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CivicTheme.green.opacity(0.08), in: Capsule())
                }
            }
        }
    }

    private func mismatchesSection(_ items: [ScorecardMismatch]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHERE THEY VOTED AGAINST YOU")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(CivicTheme.red)
            VStack(spacing: 6) {
                ForEach(items) { item in
                    mismatchRow(item)
                }
            }
        }
    }

    private func pendingSection(_ items: [ScorecardMismatch]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WAITING FOR THE VOTE")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(CivicTheme.amber)
            VStack(spacing: 6) {
                ForEach(items.prefix(5)) { item in
                    pendingRow(item)
                }
                if items.count > 5 {
                    Text("+\(items.count - 5) more pending")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.quietInk)
                }
            }
        }
    }

    private func mismatchRow(_ item: ScorecardMismatch) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(CivicTheme.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.issueTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .lineLimit(2)
                Text("You said \(item.userPosition.uppercased()) · they voted \((item.officialVote ?? "?").uppercased())")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CivicTheme.red)
            }
            Spacer()
        }
        .padding(8)
        .background(CivicTheme.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func pendingRow(_ item: ScorecardMismatch) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.fill")
                .foregroundStyle(CivicTheme.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.issueTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .lineLimit(2)
                Text("You said \(item.userPosition.uppercased()) — vote not yet recorded")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
            }
            Spacer()
        }
        .padding(8)
        .background(CivicTheme.amber.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func alignmentTint(_ pct: Int) -> Color {
        switch pct {
        case 75...: return CivicTheme.green
        case 50..<75: return CivicTheme.amber
        default: return CivicTheme.red
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(CivicTheme.green)
            Text("Building your scorecard…")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(CivicTheme.quietInk)
            Text("No filings to score yet")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("File on a few bills and your rep scorecard will populate. Alignment % fills in as each bill gets voted on.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(CivicTheme.mutedInk)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var fineprint: some View {
        Text("v1: alignment populates as Athen ingests roll-call vote data per bill. Topic mix and filing volume are real today.")
            .font(.system(size: 11))
            .foregroundStyle(CivicTheme.quietInk)
            .lineSpacing(2)
            .padding(.top, 8)
    }
}
