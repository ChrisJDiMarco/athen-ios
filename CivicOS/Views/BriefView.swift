import SwiftUI

// MARK: - Brief tab root

struct BriefView: View {
    @Environment(CivicOSStore.self) private var store
    @State private var initialLoadStarted = false
    @State private var presentedDetail: CivicBriefDigestItem?

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14, pinnedViews: []) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        BackendOfflineBanner()
                            .padding(.horizontal, 20)

                        ZipChangedBanner(hasFreshData: !store.isLoadingBriefDigest && (store.briefDigest?.items.isEmpty == false))
                            .padding(.horizontal, 20)

                        statusBar
                            .padding(.horizontal, 20)

                        if let report = store.civicBrief {
                            BriefDailyHeroCard(brief: report)
                                .padding(.horizontal, 20)
                        }

                        DeadlineRailCard(items: deadlineItems)
                            .padding(.horizontal, 20)

                        AudioBriefCard()
                            .padding(.horizontal, 20)

                        if let cohortItem = bestCohortItem,
                           let brief = cohortItem.brief {
                            CohortCard(brief: brief, profile: store.profile, issue: cohortItem.issue)
                                .padding(.horizontal, 20)
                        }

                        sectionHeader("Today's deep briefs", systemImage: "newspaper.fill")
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        ForEach(store.briefDigest?.items ?? []) { item in
                            Button {
                                Haptics.selection()
                                presentedDetail = item
                            } label: {
                                DeepBriefCard(item: item)
                                    .padding(.horizontal, 20)
                            }
                            .buttonStyle(.plain)
                        }

                        if (store.briefDigest?.items.isEmpty ?? true) {
                            if store.isLoadingBriefDigest {
                                ForEach(0..<3, id: \.self) { _ in
                                    briefSkeletonCard
                                        .padding(.horizontal, 20)
                                }
                            } else {
                                emptyState
                                    .padding(.horizontal, 20)
                                    .padding(.top, 12)
                            }
                        }

                        Color.clear.frame(height: 36)
                    }
                }
                .refreshable {
                    await store.loadBriefDigest(warm: true)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: CivicIssue.ID.self) { id in
                if let issue = store.issue(with: id) {
                    IssueDetailView(issue: issue)
                }
            }
            .task {
                if !initialLoadStarted {
                    initialLoadStarted = true
                    await store.loadBriefDigest(warm: true)
                }
            }
            .sheet(item: $presentedDetail) { item in
                BriefDetailView(item: item)
                    .environment(store)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI mode")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CivicTheme.violet)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text("Brief")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
            }
            Spacer()
            refreshButton
        }
    }

    private var subtitle: String {
        let location = store.profile?.displayLocation ?? "your area"
        let count = store.briefDigest?.items.count ?? 0
        if count == 0 { return "Loading explainers for \(location)…" }
        return "\(count) explainers personalized for \(location)"
    }

    private var refreshButton: some View {
        Menu {
            Button {
                Haptics.selection()
                Task { await store.refreshBriefFeed() }
            } label: {
                Label("Pull fresh briefs", systemImage: "sparkles")
            }
            Button {
                Haptics.selection()
                Task { await store.refreshCivicDataFromBriefTab() }
            } label: {
                Label("Refresh civic data", systemImage: "arrow.triangle.2.circlepath")
            }
            Divider()
            Button {
                Haptics.selection()
                Task { await store.forceRegenerateAllBriefs() }
            } label: {
                Label("Regenerate all briefs (costs Claude calls)", systemImage: "arrow.clockwise.circle.fill")
            }
        } label: {
            ZStack {
                Circle().fill(CivicTheme.violet.opacity(0.14))
                Circle().stroke(CivicTheme.violet.opacity(0.22), lineWidth: 1)
                if store.isLoadingBriefDigest || store.isRunningOrchestrator {
                    ProgressView().tint(CivicTheme.violet)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                }
            }
            .frame(width: 42, height: 42)
        }
        .accessibilityLabel("Brief actions")
        .disabled(store.isLoadingBriefDigest || store.isRunningOrchestrator)
    }

    @ViewBuilder
    private var statusBar: some View {
        if let err = store.lastBriefError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CivicTheme.amber)
                Text(err)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(CivicTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.amber.opacity(0.18), lineWidth: 1))
        }
    }

    private var deadlineItems: [DeadlineItem] {
        let items = store.briefDigest?.items ?? []
        let cutoff = Date.now.addingTimeInterval(45 * 86400)
        return items
            .compactMap { item -> DeadlineItem? in
                guard let date = item.issue.voteDate, date >= .now, date <= cutoff else { return nil }
                return DeadlineItem(
                    id: item.issueId,
                    title: item.brief?.headline ?? item.issue.title,
                    jurisdiction: item.issue.jurisdiction,
                    scope: item.issue.scope,
                    impactLevel: item.issue.impactLevel,
                    voteDate: date
                )
            }
            .sorted { $0.voteDate < $1.voteDate }
    }

    private var bestCohortItem: CivicBriefDigestItem? {
        guard let factors = store.profile?.factors, !factors.isEmpty else {
            return store.briefDigest?.items.first(where: { $0.brief != nil })
        }
        let preferred = preferredCohorts(for: factors)
        return store.briefDigest?.items.first { item in
            guard let brief = item.brief else { return false }
            return brief.cohortProjections.contains { preferred.contains($0.cohort) }
        } ?? store.briefDigest?.items.first(where: { $0.brief != nil })
    }

    private func preferredCohorts(for factors: Set<CivicProfileFactor>) -> Set<CivicBriefAnalysis.CohortProjection.Cohort> {
        var out: Set<CivicBriefAnalysis.CohortProjection.Cohort> = [.general]
        for factor in factors {
            switch factor {
            case .renter: out.insert(.renter)
            case .homeowner: out.insert(.homeowner)
            case .parent: out.insert(.parent)
            case .commuter: out.insert(.commuter)
            case .businessOwner: out.insert(.businessOwner)
            case .accessibilityNeeds: out.insert(.olderAdult)
            case .climateFlood: out.insert(.general)
            }
        }
        return out
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CivicTheme.violet)
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CivicTheme.violet)
                .textCase(.uppercase)
                .tracking(0.5)
            Rectangle()
                .fill(CivicTheme.violet.opacity(0.25))
                .frame(height: 1)
        }
    }

    private var briefSkeletonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(CivicTheme.hairline)
                    .frame(width: 70, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(CivicTheme.hairline)
                    .frame(width: 50, height: 12)
            }
            RoundedRectangle(cornerRadius: 6)
                .fill(CivicTheme.hairline)
                .frame(height: 22)
            RoundedRectangle(cornerRadius: 6)
                .fill(CivicTheme.hairline.opacity(0.7))
                .frame(width: 220, height: 14)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(CivicTheme.hairline.opacity(0.5))
                    .frame(height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(CivicTheme.hairline.opacity(0.5))
                    .frame(height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(CivicTheme.hairline.opacity(0.5))
                    .frame(width: 180, height: 10)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(CivicTheme.hairline, lineWidth: 1))
        .redacted(reason: .placeholder)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(CivicTheme.quietInk)
            Text("No briefs loaded yet")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Pull to refresh or tap ✨ above. Briefs run through Claude in seconds.")
                .font(.system(size: 13))
                .foregroundStyle(CivicTheme.mutedInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

struct DeadlineItem: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let jurisdiction: String
    let scope: String
    let impactLevel: String
    let voteDate: Date

    var countdownLabel: String {
        let interval = voteDate.timeIntervalSinceNow
        if interval < 0 { return "Closed" }
        if interval < 3600 { return "\(max(1, Int(interval / 60)))m" }
        if interval < 86400 { return "\(max(1, Int(interval / 3600)))h" }
        let days = Int(interval / 86400)
        return "\(days)d"
    }

    var tint: Color {
        switch impactLevel {
        case "urgent": return CivicTheme.red
        case "material": return CivicTheme.amber
        default: return CivicTheme.cyan
        }
    }
}

#Preview {
    BriefView().environment(CivicOSStore())
}
