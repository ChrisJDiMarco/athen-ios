import SwiftUI

struct DashboardView: View {
    @Environment(CivicOSStore.self) private var store
    @State private var filter: IssueDashboardFilter = .radar
    @State private var exportingCSV: Bool = false
    @State private var csvShareItem: CSVShareItem?
    @State private var showingProfile: Bool = false

    private var visibleIssues: [CivicIssue] { filteredInsights.map(\.issue) }

    private var filteredInsights: [CivicRadarInsight] {
        store.radarInsights.filter { insight in
            switch filter {
            case .radar:
                return true
            case .actNow:
                return insight.priority == .actNow
            case .affectsMe:
                return insight.issue.isPersonallyRelevant(to: store.profile)
            case .power:
                return true
            case .social:
                return true
            case .saved:
                return store.isBookmarked(insight.issue)
            case .local:
                if case .localPhilly = insight.issue.scope { return true }
                return false
            }
        }
        .sorted { lhs, rhs in
            switch filter {
            case .power:
                if lhs.issue.trustScore != rhs.issue.trustScore {
                    return lhs.issue.trustScore > rhs.issue.trustScore
                }
                return lhs.score > rhs.score
            case .social:
                let leftHeat = store.socialHeat(for: lhs.issue.id)
                let rightHeat = store.socialHeat(for: rhs.issue.id)
                if leftHeat != rightHeat { return leftHeat > rightHeat }
                return lhs.score > rhs.score
            default:
                return lhs.score > rhs.score
            }
        }
    }

    var body: some View {
        // No inner NavigationStack — we rely on whatever parent nav stack
        // pushed this view (Home, or other entry points). Nested stacks
        // would silently break back-navigation and route-pushing for issue
        // detail links.
        ZStack {
            CivicTheme.screenBackground
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        dashboardHeader
                        if !store.radarInsights.isEmpty {
                            radarCommandCenter
                            civicLoopCard
                        }
                        CivicPulseCard()
                        filterBar
                        if !filteredInsights.isEmpty {
                            actionTimeRail
                            radarQueue
                            powerMapSection
                        }
                        if store.isRefreshingIssues {
                            HStack(spacing: 8) {
                                ProgressView().tint(CivicTheme.cyan)
                                Text("Loading items…")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(CivicTheme.mutedInk)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if visibleIssues.isEmpty {
                            emptyState
                            if filter == .local && store.profile != nil && !store.hasLocalIssues {
                                localComingSoonCard
                            }
                        } else {
                            if let firstIssue = visibleIssues.first {
                                NavigationLink(value: firstIssue.id) {
                                    FeaturedImpactCard(issue: firstIssue)
                                }
                                .buttonStyle(.plain)
                            }

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ],
                                spacing: 12
                            ) {
                                ForEach(visibleIssues.dropFirst()) { issue in
                                    NavigationLink(value: issue.id) {
                                        CompactImpactCard(issue: issue)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if filter == .local && store.profile != nil && !store.hasLocalIssues {
                                localComingSoonCard
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
                .refreshable {
                    await store.refreshIssues()
                }
            }
        .navigationTitle("All items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Haptics.selection()
                    showingProfile = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CivicTheme.mutedInk)
                }
                .accessibilityLabel("Profile and settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.selection()
                    Task { await exportCSV() }
                } label: {
                    if exportingCSV {
                        ProgressView().tint(CivicTheme.cyan).scaleEffect(0.85)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CivicTheme.cyan)
                    }
                }
                .disabled(exportingCSV)
                .accessibilityLabel("Export filtered issues as CSV")
            }
        }
        .sheet(isPresented: $showingProfile) {
            NavigationStack {
                ProfileView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { showingProfile = false }
                                .foregroundStyle(CivicTheme.cyan)
                        }
                    }
            }
            .environment(store)
        }
        .sheet(item: $csvShareItem) { item in
            ShareSheet(activityItems: [item.url])
                .ignoresSafeArea()
        }
        .task {
            if store.issues.isEmpty {
                await store.refreshIssues()
            }
        }
    }

    private func exportCSV() async {
        exportingCSV = true
        defer { exportingCSV = false }
        let scopeQ: String? = {
            if case .local = filter { return "local-philly" }
            return nil
        }()
        let data = await store.exportIssuesCSV(scope: scopeQ, stateCode: store.profile?.stateCode, q: nil)
        guard let data = data else { return }
        let filename = "athen-issues-\(ISO8601DateFormatter().string(from: .now).prefix(10)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            csvShareItem = CSVShareItem(url: url)
        } catch {
            // Silent — surface in toast if we add error UX later.
        }
    }

    private struct CSVShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Radar")
                        .font(.system(size: 34, weight: .bold, design: .default))
                        .foregroundStyle(CivicTheme.ink)

                    Text(headerSubtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                }

                Spacer()

                RectBadge(
                    text: store.profile == nil ? "Set ZIP" : "Verified",
                    systemImage: store.profile == nil ? "mappin.and.ellipse" : "checkmark.shield.fill",
                    tint: store.profile == nil ? CivicTheme.amber : CivicTheme.green
                )
            }

            Text(headerBlurb)
                .font(.system(size: 16, weight: .regular))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerSubtitle: String {
        if let profile = store.profile {
            return "\(profile.displayLocation) · ZIP \(profile.zipCode)"
        }
        return "Set your ZIP to personalize the radar"
    }

    private var headerBlurb: String {
        if store.profile == nil {
            return "Tell us where you live and we'll surface federal, state, and local items that actually apply to you — translated and ready to file."
        }
        let count = store.visibleIssues.count
        return "\(count) item\(count == 1 ? "" : "s") ranked by deadline, personal relevance, source confidence, social momentum, and power map."
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(IssueDashboardFilter.allCases) { option in
                    let active = filter == option
                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            filter = option
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: option.systemImage)
                                .font(.system(size: 11, weight: .bold))
                            Text(option.label)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(active ? .white : option.tint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(active ? option.tint : option.tint.opacity(0.10), in: Capsule())
                        .overlay(Capsule().stroke(option.tint.opacity(active ? 0 : 0.22), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    private var radarCommandCenter: some View {
        CivicGlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Today’s civic command center", systemImage: "target")
                        Text(commandCenterTitle)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    RectBadge(text: "\(store.radarInsights.count) live", systemImage: "waveform.path.ecg", tint: CivicTheme.cyan)
                }

                VStack(spacing: 10) {
                    ForEach(Array(store.radarInsights.prefix(3).enumerated()), id: \.element.id) { index, insight in
                        NavigationLink(value: insight.issue.id) {
                            commandRow(index: index, insight: insight)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    Haptics.selection()
                    store.queueAssistantPrompt(commandCenterPrompt)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                        Text("Ask Athen for my 10-minute plan")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(CivicTheme.violet, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var commandCenterTitle: String {
        let count = min(3, store.radarInsights.count)
        if count == 0 { return "Nothing urgent yet" }
        return "\(count) thing\(count == 1 ? "" : "s") worth your attention"
    }

    private var commandCenterPrompt: String {
        let items = store.radarInsights.prefix(3).map {
            "- \($0.issue.title): \($0.reason) Next move: \($0.recommendedAction). Timing: \($0.timing)"
        }.joined(separator: "\n")
        return """
        Build me a practical 10-minute civic plan for today.
        Location: \(store.profile?.displayLocation ?? "not set")
        Top radar items:
        \(items)

        Keep it concrete: what to read first, what to file or save, who to share with, and what to ignore for now.
        """
    }

    private func commandRow(index: Int, insight: CivicRadarInsight) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(insight.priority.tint, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    RectBadge(text: insight.issue.actionTimeEstimate(alreadySent: store.status(for: insight.issue).isSent), systemImage: "timer", tint: insight.priority.tint)
                    RectBadge(text: insight.issue.civicLoopStep(alreadySent: store.status(for: insight.issue).isSent), systemImage: "arrow.triangle.2.circlepath", tint: CivicTheme.green)
                }
                Text(insight.issue.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(insight.reason)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
                .padding(.top, 5)
        }
        .padding(12)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private var civicLoopCard: some View {
        CivicGlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Engagement loop", systemImage: "arrow.triangle.2.circlepath")
                HStack(spacing: 8) {
                    loopStep("Know", "plain English", CivicTheme.cyan)
                    loopStep("Care", "your stake", CivicTheme.violet)
                    loopStep("Act", "2–10 min", CivicTheme.amber)
                    loopStep("Track", "outcomes", CivicTheme.green)
                }
                Text("Athen’s job is to close the loop: explain the issue, show why it matters to you, help you act, then bring back replies, votes, and changes.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loopStep(_ title: String, _ detail: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
            Text(detail)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CivicTheme.quietInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private var actionTimeRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(filteredInsights.prefix(8)) { insight in
                    NavigationLink(value: insight.issue.id) {
                        VStack(alignment: .leading, spacing: 8) {
                            RectBadge(
                                text: insight.issue.actionTimeEstimate(alreadySent: store.status(for: insight.issue).isSent),
                                systemImage: "timer",
                                tint: insight.priority.tint
                            )
                            Text(insight.recommendedAction)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(CivicTheme.ink)
                                .lineLimit(2)
                            Text(insight.issue.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CivicTheme.mutedInk)
                                .lineLimit(3)
                        }
                        .padding(13)
                        .frame(width: 210, height: 142, alignment: .topLeading)
                        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    private var powerMapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Power map", systemImage: "building.columns.fill")
                Spacer()
                Text("who decides")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            ForEach(filteredInsights.prefix(3)) { insight in
                NavigationLink(value: insight.issue.id) {
                    powerRow(insight.issue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func powerRow(_ issue: CivicIssue) -> some View {
        let map = issue.powerMap
        return CivicGlassCard(padding: 13) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(issue.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                            .lineLimit(2)
                        Text(map.venue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CivicTheme.cyan)
                    }
                    Spacer()
                    RectBadge(text: "\(issue.trustScore)%", systemImage: "checkmark.shield.fill", tint: issue.trustScore >= 80 ? CivicTheme.green : CivicTheme.amber)
                }
                HStack(spacing: 8) {
                    powerPill("Decider", map.decisionMaker, CivicTheme.violet)
                    powerPill("Channel", map.publicChannel, CivicTheme.amber)
                }
                Text(map.pressurePoint)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineLimit(2)
            }
        }
    }

    private func powerPill(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CivicTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyState: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("No items in your feed yet", systemImage: "tray")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.amber)
                Text(store.issues.isEmpty
                    ? "\(AppBrand.name) is rolling out coverage city by city. Pull to refresh to check for new items, or connect a backend from profile → AI backend."
                    : "Items exist but none match your current jurisdiction and interests. Try updating interests from Radar → profile, or check back tomorrow.")
                    .font(.system(size: 14))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
                if let err = store.lastIssueRefreshError {
                    Text(err)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.red)
                }
                // Demo-mode load button removed — Athen shows real civic
                // items only. When the feed is empty, the user should connect
                // a backend or wait for the orchestrator to pull data.
                EmptyView()
            }
        }
    }

    private var radarQueue: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Action radar")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Text("\(readyCountForFilter) ready")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
            }

            ForEach(filteredInsights.prefix(4)) { insight in
                NavigationLink(value: insight.issue.id) {
                    RadarInsightCard(insight: insight)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var readyCountForFilter: Int {
        filteredInsights.filter { insight in
            !store.status(for: insight.issue).isSent && !insight.issue.hasVotePassed
        }.count
    }

    private var localComingSoonCard: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Local issues for \(store.profile?.localityLabel ?? store.profile?.stateName ?? "your city")", systemImage: "building.2")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.violet)
                Text("Athen ingests city-council and county-board agendas for 13 major US cities (Philadelphia, NYC, Chicago, LA, DC, Boston, Seattle, Portland, SF, Detroit, Houston, Austin, Minneapolis). If yours isn't here yet, federal + state items above still apply.")
                    .font(.system(size: 14))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
            }
        }
    }
}

private enum IssueDashboardFilter: String, CaseIterable, Identifiable {
    case radar
    case actNow
    case affectsMe
    case power
    case social
    case saved
    case local

    var id: String { rawValue }

    var label: String {
        switch self {
        case .radar: "Radar"
        case .actNow: "Now"
        case .affectsMe: "Me"
        case .power: "Power"
        case .social: "People"
        case .saved: "Saved"
        case .local: "Local"
        }
    }

    var systemImage: String {
        switch self {
        case .radar: "dot.radiowaves.left.and.right"
        case .actNow: "bolt.fill"
        case .affectsMe: "person.crop.circle.badge.checkmark"
        case .power: "building.columns.fill"
        case .social: "person.2.wave.2.fill"
        case .saved: "bookmark.fill"
        case .local: "building.2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .radar: CivicTheme.cyan
        case .actNow: CivicTheme.amber
        case .affectsMe: CivicTheme.violet
        case .power: CivicTheme.cyan
        case .social: CivicTheme.green
        case .saved: CivicTheme.amber
        case .local: CivicTheme.violet
        }
    }
}

private struct CivicPulseCard: View {
    @Environment(CivicOSStore.self) private var store

    var body: some View {
        CivicGlassCard {
            HStack(spacing: 12) {
                PulseMetric(
                    value: "\(store.visibleIssues.count)",
                    label: "Impact items",
                    tint: CivicTheme.cyan
                )

                Divider()
                    .overlay(CivicTheme.hairline)

                PulseMetric(
                    value: nearestVoteRelative,
                    label: "Nearest vote",
                    tint: CivicTheme.amber
                )

                Divider()
                    .overlay(CivicTheme.hairline)

                PulseMetric(
                    value: "\(store.sentCount)",
                    label: "Filed",
                    tint: CivicTheme.green
                )
            }
        }
    }

    private var nearestVoteRelative: String {
        let upcoming = store.visibleIssues
            .filter { $0.voteDate > .now }
            .sorted { $0.voteDate < $1.voteDate }
            .first
        guard let next = upcoming else { return "—" }
        let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: next.voteDate).day ?? 0)
        return days == 0 ? "Today" : "\(days)d"
    }
}

private struct PulseMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CivicTheme.quietInk)
                .textCase(.uppercase)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    DashboardView()
        .environment(CivicOSStore())
        .preferredColorScheme(.light)
}
