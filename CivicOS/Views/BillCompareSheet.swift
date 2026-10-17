import SwiftUI

/// Pick two bookmarked bills and see them side-by-side. Particularly useful
/// for housing/climate/budget cycles where multiple bills compete on similar
/// territory and the user wants a quick "which one actually does more."
///
/// Step 1: select left bill, then right bill from bookmarks
/// Step 2: side-by-side compare card showing key facts, fiscal impact,
/// both-sides summary, vote dates
struct BillCompareSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var leftIssueId: CivicIssue.ID?
    @State private var rightIssueId: CivicIssue.ID?

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        intro
                        pickerSection(side: .left)
                        pickerSection(side: .right)
                        if let leftBrief, let rightBrief {
                            comparisonGrid(left: leftBrief, right: rightBrief)
                        } else if leftIssueId != nil && rightIssueId != nil {
                            loadingState
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
            }
            .navigationTitle("Compare bills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
            .task(id: leftIssueId) { await loadBriefIfNeeded(leftIssueId) }
            .task(id: rightIssueId) { await loadBriefIfNeeded(rightIssueId) }
        }
    }

    enum Side { case left, right }

    private var bookmarkedIssues: [CivicIssue] {
        store.bookmarkedIssues
    }

    private var leftBrief: CivicBriefAnalysis? {
        guard let id = leftIssueId else { return nil }
        return store.brief(for: id.uuidString)
    }

    private var rightBrief: CivicBriefAnalysis? {
        guard let id = rightIssueId else { return nil }
        return store.brief(for: id.uuidString)
    }

    private var leftIssue: CivicIssue? {
        guard let id = leftIssueId else { return nil }
        return store.issue(with: id)
    }

    private var rightIssue: CivicIssue? {
        guard let id = rightIssueId else { return nil }
        return store.issue(with: id)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AIDisclosureChip(surface: .brief)
                Spacer()
            }
            Text("Compare any two bookmarked bills")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Athen pulls the AI brief for each and lines up key facts, fiscal impact, and arguments so you can see how they differ at a glance.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
        }
    }

    private func pickerSection(side: Side) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(side == .left ? "BILL A" : "BILL B")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(CivicTheme.mutedInk)
            if bookmarkedIssues.isEmpty {
                emptyBookmarksHint
            } else {
                Menu {
                    ForEach(bookmarkedIssues) { issue in
                        Button(issue.title) {
                            Haptics.selection()
                            switch side {
                            case .left: leftIssueId = issue.id
                            case .right: rightIssueId = issue.id
                            }
                        }
                    }
                } label: {
                    pickerLabel(side: side)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pickerLabel(side: Side) -> some View {
        let issue = side == .left ? leftIssue : rightIssue
        return HStack(spacing: 10) {
            Image(systemName: issue == nil ? "plus.circle.dashed" : "checkmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(issue == nil ? CivicTheme.mutedInk : CivicTheme.cyan)
            Text(issue?.title ?? "Pick a bookmarked bill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CivicTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CivicTheme.quietInk)
        }
        .padding(14)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private var emptyBookmarksHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No bookmarks yet", systemImage: "bookmark.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CivicTheme.amber)
            Text("Tap the bookmark icon on any bill detail to save it. Once you have two saved, you can compare them here.")
                .font(.system(size: 12))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(CivicTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().tint(CivicTheme.violet)
            Text("Loading both briefs…")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
    }

    private func comparisonGrid(left: CivicBriefAnalysis, right: CivicBriefAnalysis) -> some View {
        VStack(spacing: 10) {
            comparisonRow(label: "Headline", left: left.headline, right: right.headline)
            comparisonRow(label: "Fiscal impact", left: left.fiscalImpact, right: right.fiscalImpact)
            if let leftSupporters = left.twoSides.first(where: { $0.stance == .support })?.argument,
               let rightSupporters = right.twoSides.first(where: { $0.stance == .support })?.argument {
                comparisonRow(label: "Supporters say", left: leftSupporters, right: rightSupporters)
            }
            if let leftCritics = left.twoSides.first(where: { $0.stance == .concern })?.argument,
               let rightCritics = right.twoSides.first(where: { $0.stance == .concern })?.argument {
                comparisonRow(label: "Critics say", left: leftCritics, right: rightCritics)
            }
            if let leftKeyFact = left.keyFacts.first, let rightKeyFact = right.keyFacts.first {
                comparisonRow(label: "Top fact", left: "\(leftKeyFact.label): \(leftKeyFact.value)", right: "\(rightKeyFact.label): \(rightKeyFact.value)")
            }
        }
    }

    private func comparisonRow(label: String, left: String, right: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(CivicTheme.mutedInk)
            HStack(alignment: .top, spacing: 10) {
                cell(text: left, tint: CivicTheme.cyan)
                cell(text: right, tint: CivicTheme.violet)
            }
        }
        .padding(.bottom, 4)
    }

    private func cell(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 12))
            .lineSpacing(3)
            .foregroundStyle(CivicTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.20), lineWidth: 1))
    }

    private func loadBriefIfNeeded(_ id: CivicIssue.ID?) async {
        guard let id else { return }
        guard store.brief(for: id.uuidString) == nil else { return }
        await store.generateBrief(for: id.uuidString)
    }
}
