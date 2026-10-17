import SwiftUI

struct HomeView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    let selectTab: (MainTabView.Tab) -> Void
    @State private var showingHelp: Bool = false
    @State private var presentedBrief: CivicBriefDigestItem?
    @State private var path = NavigationPath()
    @State private var showPetitions: Bool = false
    @State private var showVoterHub: Bool = false
    @State private var showLifeEvent: Bool = false
    @State private var showDirectory: Bool = false
    @State private var showTopicsPicker: Bool = false
    @State private var showContextPicker: Bool = false
    @State private var showProfileSheet: Bool = false
    @State private var refreshToast: String?
    @State private var showInbox: Bool = false
    @State private var refreshStreamStartedAt: Date?
    @State private var refreshStreamRows: [RefreshProgressDrawer.Row] = []
    @State private var refreshStreamSummary: RefreshProgressDrawer.Summary?
    @State private var refreshStreamError: String?
    @State private var refreshStreamTask: Task<Void, Never>?
    @State private var refreshDrawerVisible: Bool = false
    @AppStorage("athen.home.viewMode.v1") private var homeModeRaw: String = HomeMode.today.rawValue
    // News tab cache — persisted to UserDefaults so content survives app
    // launches AND tab switches. Only refetched when the user explicitly
    // taps the reload button (or first-ever visit with no cache).
    @State private var newsItems: [NewsHeadline] = HomeNewsCache.shared.loadItems()
    @State private var newsIsLoading: Bool = false
    @State private var newsError: String?
    @State private var newsSummary: String? = HomeNewsCache.shared.loadSummary()
    @State private var newsSpinAngle: Double = 0

    enum HomeMode: String, CaseIterable, Identifiable {
        case today, news, pulse
        var id: String { rawValue }
        var label: String {
            switch self {
            case .today: "Today"
            case .news: "News"
            case .pulse: "Pulse"
            }
        }
        var icon: String {
            switch self {
            case .today: "sun.max.fill"
            case .news: "newspaper.fill"
            case .pulse: "waveform.path.ecg"
            }
        }
        var tint: Color {
            switch self {
            case .today: CivicTheme.amber
            case .news: CivicTheme.cyan
            case .pulse: CivicTheme.violet
            }
        }
    }

    private var homeMode: HomeMode {
        get { HomeMode(rawValue: homeModeRaw) ?? .today }
        nonmutating set { homeModeRaw = newValue.rawValue }
    }

    private var nextVoteIssue: CivicIssue? {
        store.visibleIssues
            .filter { $0.voteDate > .now }
            .sorted { $0.voteDate < $1.voteDate }
            .first
    }

    private var topFederalIssue: CivicIssue? {
        store.visibleIssues.first {
            if case .federal = $0.scope { return true }
            return false
        }
    }

    /// Suppress the radar card if it would be redundant with the daily hero.
    /// The hero already surfaces the top deadline once it has real Brief
    /// content; showing the radar in that case duplicates the same item.
    private var shouldShowRadar: Bool {
        guard let insight = store.topRadarInsight else { return false }
        // Suppress when the hero is already pointing at the same issue.
        if let heroHeadline = store.civicBrief?.headline, !heroHeadline.isEmpty {
            return heroHeadline != insight.issue.title
        }
        return true
    }

    /// Hide source-pulse when source data is bare (no real signal).
    private var shouldShowSourcePulse: Bool {
        if let health = store.civicBrief?.sourceHealth {
            return (health.registeredSources ?? 0) > 0 || health.activeSourceHosts > 0
        }
        return activeSourceHostCount > 1
    }

    /// "Next vote" card is redundant if nextVoteIssue is already the radar's
    /// top insight (they'd both point to the same item).
    private var shouldShowNextVoteCard: Bool {
        guard let next = nextVoteIssue else { return false }
        return store.topRadarInsight?.issue.id != next.id
    }

    /// Federal card is filler unless the user actually has federal-scope items.
    private var shouldShowFederalCard: Bool {
        guard let federal = topFederalIssue else { return false }
        // If the radar already picked this one, don't show it again.
        return store.topRadarInsight?.issue.id != federal.id
    }

    /// Picks the hero variant based on local time. Drives copy + CTA only;
    /// the visual shell is the same so the hero never feels jarring.
    private enum HeroMode {
        case morning   // 5am–noon: agenda + audio briefing
        case afternoon // noon–6pm: countdown / urgency
        case evening   // 6pm–11pm: what changed today
        case night     // 11pm–5am: quiet recap
    }

    private var heroMode: HeroMode {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return .morning
        case 12..<18: return .afternoon
        case 18..<23: return .evening
        default: return .night
        }
    }

    private var heroLabelPrefix: String {
        switch heroMode {
        case .morning: return "Today in"
        case .afternoon: return "This afternoon in"
        case .evening: return "Tonight in"
        case .night: return "Late in"
        }
    }

    private var heroIcon: String {
        switch heroMode {
        case .morning: return "sun.max.fill"
        case .afternoon: return "sun.haze.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }

    private var heroGradient: LinearGradient {
        switch heroMode {
        case .morning:
            return LinearGradient(
                colors: [CivicTheme.cyan, Color(red: 0.10, green: 0.46, blue: 0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .afternoon:
            return LinearGradient(
                colors: [Color(red: 0.95, green: 0.55, blue: 0.20), Color(red: 0.85, green: 0.30, blue: 0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .evening:
            return LinearGradient(
                colors: [Color(red: 0.50, green: 0.30, blue: 0.85), Color(red: 0.25, green: 0.15, blue: 0.60)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .night:
            return LinearGradient(
                colors: [Color(red: 0.15, green: 0.18, blue: 0.30), Color(red: 0.08, green: 0.10, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var heroCTALabel: String {
        switch heroMode {
        case .morning: return "Make my 5-minute plan"
        case .afternoon:
            if nextVoteIssue != nil { return "Open the urgent item" }
            return "What needs me today"
        case .evening:
            if !store.diffEvents.isEmpty { return "See what changed today" }
            return "Recap today's civics"
        case .night: return "Catch up tomorrow morning"
        }
    }

    private var heroCTAIcon: String {
        switch heroMode {
        case .morning: return "sparkles"
        case .afternoon: return "bolt.fill"
        case .evening: return "sparkles.rectangle.stack.fill"
        case .night: return "moon.zzz.fill"
        }
    }

    private func handleHeroCTA() {
        switch heroMode {
        case .morning:
            store.queueAssistantPrompt("Give me a 5-minute action plan for today. Use my location, the top civic deadlines, my public-service matches, and anything I still need to prepare.")
            selectTab(.assistant)
        case .afternoon:
            if let issue = nextVoteIssue {
                path.append(issue.id)
            } else {
                // No urgent item — ask the assistant what's most worth my time
                store.queueAssistantPrompt("Nothing urgent on my radar this afternoon. What's the most worthwhile civic thing I could do right now in \(store.profile?.stateName ?? "my area")?")
                selectTab(.assistant)
            }
        case .evening:
            if let first = store.diffEvents.first {
                path.append(first.issueID)
            } else {
                // No bookmark diffs — ask the assistant to recap today
                store.queueAssistantPrompt("Recap today's civic activity for me — what happened in Congress, my state legislature, and locally in \(store.profile?.localityLabel ?? store.profile?.stateName ?? "my area")? Keep it tight and tell me one thing worth knowing for tomorrow.")
                selectTab(.assistant)
            }
        case .night:
            store.queueAssistantPrompt("Give me a quick civic catch-up I can read in 60 seconds before bed — what shipped today, what's pending tomorrow.")
            selectTab(.assistant)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()

                GeometryReader { geo in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            header
                            BackendOfflineBanner()
                            ZipChangedBanner(hasFreshData: !store.isRefreshingIssues && !store.issues.isEmpty)

                            if store.profile == nil {
                                zipPromptCard
                            } else if isFirstRunLoading {
                                firstRunLoadingState
                            } else {
                                if let error = store.lastIssueRefreshError ?? store.lastOrchestratorError {
                                    refreshErrorCard(error)
                                }

                                // Election Day takes over — single most important
                                // signal in the app. Everything else compresses.
                                if store.isElectionDay {
                                    electionDayBanner
                                }

                                // View switcher — Today / News / Pulse.
                                // Replaces the old metric strip; pulse moved to You.
                                homeModeSwitcher

                                Group {
                                    if homeMode == .today { todayModeContent }
                                    else if homeMode == .news { newsModeContent }
                                    else { pulseModeContent }
                                }

                                // Last refresh timestamp at the bottom
                                lastRefreshFooter
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                        .padding(.bottom, 28)
                        // Force content to exact screen width (capped 680 on iPad).
                        // Without this, ANY child wider than the screen lets UIKit's
                        // underlying UIScrollView pan horizontally — `.vertical`
                        // axis only controls bouncing, not panning constraints.
                        .frame(width: min(geo.size.width, 680), alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    }
                    .refreshable {
                        await refreshWithToast()
                    }
                    .overlay(alignment: .top) { refreshToastOverlay }
                    .overlay(alignment: .bottom) { refreshDrawerOverlay }
                    .task {
                        if store.backendStatus == .unknown {
                            await store.checkBackendHealth()
                        }
                        // First-run: if profile is set but we have no data at all,
                        // kick off the full orchestrator so the user gets a real
                        // feed within ~10s instead of an empty Home.
                        if store.profile != nil
                            && store.issues.isEmpty
                            && !hasTriggeredFirstRun {
                            hasTriggeredFirstRun = true
                            await store.runFullRefresh()
                        } else if store.profile != nil && store.issues.isEmpty {
                            await store.refreshIssues()
                        }
                        // Warm the Brief cache + generate top 5 in parallel so
                        // tapping a brief feels instant.
                        if store.profile != nil && (store.briefDigest?.items.isEmpty ?? true) {
                            await store.loadBriefDigest(warm: true)
                        }
                        // Schedule local push nudges for upcoming votes on
                        // any bookmarked issues. Runs every app foreground
                        // (cheap + idempotent).
                        store.syncPredictiveNudges()
                        // Refresh Composio integration status so any bill
                        // detail page sees the latest "is Gmail connected?"
                        // without the user having to visit Connected apps.
                        if store.integrationStatusByApp.isEmpty {
                            await store.loadIntegrations()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .onChange(of: scenePhase) { _, newPhase in
                // Smart auto-refresh on app foreground. Throttled to once
                // every 10 minutes so a quick app-switch doesn't hammer the
                // sources. Silent — no toast — to stay out of the way.
                guard newPhase == .active,
                      store.profile != nil,
                      !store.issues.isEmpty
                else { return }
                Task { _ = await store.runFullRefresh(minimumAge: 600) }
            }
            .navigationDestination(for: CivicIssue.ID.self) { id in
                if let issue = store.issue(with: id) {
                    IssueDetailView(issue: issue)
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .groups: GroupsListView()
                case .issues: DashboardView()
                }
            }
            .sheet(isPresented: $showingHelp) {
                NavigationStack {
                    HelpView(askAssistant: { prompt in
                        store.queueAssistantPrompt(prompt)
                        showingHelp = false
                        selectTab(.assistant)
                    })
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showingHelp = false }
                                .foregroundStyle(CivicTheme.cyan)
                        }
                    }
                }
                .environment(store)
            }
            .sheet(item: $presentedBrief) { item in
                BriefDetailView(item: item)
                    .environment(store)
            }
            .sheet(isPresented: $showPetitions) {
                PetitionsView()
                    .environment(store)
            }
            .sheet(isPresented: $showVoterHub) {
                VoterHubView()
                    .environment(store)
            }
            .sheet(isPresented: $showLifeEvent) {
                LifeEventComposerView()
                    .environment(store)
            }
            .sheet(isPresented: $showDirectory) {
                OfficialsDirectoryView()
                    .environment(store)
            }
            .sheet(isPresented: $showTopicsPicker) {
                TopicsPickerSheet(initial: store.profile?.interests ?? [])
                    .environment(store)
            }
            .sheet(isPresented: $showContextPicker) {
                ContextPickerSheet(initial: store.profile?.factors ?? [])
                    .environment(store)
            }
            .sheet(isPresented: $showInbox) {
                NotificationsInboxView()
                    .environment(store)
            }
            .sheet(isPresented: $showProfileSheet) {
                NavigationStack {
                    ProfileView()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close") { showProfileSheet = false }
                                    .foregroundStyle(CivicTheme.cyan)
                            }
                        }
                }
                .environment(store)
            }
            .task {
                // Best-effort loads — only the tile-level metadata.
                if store.petitions.isEmpty {
                    _ = await store.loadPetitions(.openOnly)
                }
                if store.upcomingElections.isEmpty {
                    await store.loadVoterRail()
                }
            }
        }
    }

    @ViewBuilder
    private var petitionsTile: some View {
        let openCount = store.petitionStats?.open ?? store.petitions.filter { $0.status == .open }.count
        let signedCount = store.signedPetitionIDs.count
        Button {
            Haptics.selection()
            showPetitions = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(CivicTheme.violet.opacity(0.16))
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(petitionsTileTitle(openCount: openCount, signedCount: signedCount))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        if openCount == 0 {
                            Text("NEW")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(CivicTheme.violet, in: Capsule())
                        }
                    }
                    Text(petitionsTileSubtitle(openCount: openCount))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CivicTheme.violet.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.violet.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func petitionsTileTitle(openCount: Int, signedCount: Int) -> String {
        if signedCount > 0 { return "Petitions · you've signed \(signedCount)" }
        if openCount == 0 { return "Start a petition" }
        return "\(openCount) open petition\(openCount == 1 ? "" : "s")"
    }

    private func petitionsTileSubtitle(openCount: Int) -> String {
        if openCount == 0 {
            return "Rally a collective voice. One demand, many signers, delivered to the right official."
        }
        return "Sign on, see signer walls, or start your own. Petitions auto-deliver when threshold or deadline hits."
    }

    @ViewBuilder
    private var voterHubTile: some View {
        Button {
            Haptics.selection()
            showVoterHub = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(voterHubTint.opacity(0.16))
                    Image(systemName: voterHubIcon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(voterHubTint)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(voterHubTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        if store.isElectionDay {
                            Text("TODAY")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(CivicTheme.red, in: Capsule())
                        }
                    }
                    Text(voterHubSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(voterHubTint.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(voterHubTint.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var voterHubTint: Color {
        if store.isElectionDay { return CivicTheme.red }
        if let next = store.nextElection, let days = next.daysUntil, days <= 14 {
            return CivicTheme.amber
        }
        return CivicTheme.violet
    }

    private var voterHubIcon: String {
        if store.isElectionDay { return "checkmark.seal.fill" }
        return "doc.text.image.fill"
    }

    private var voterHubTitle: String {
        if store.isElectionDay { return "Election Day — your plan" }
        if let next = store.nextElection, let days = next.daysUntil {
            if days == 1 { return "Election tomorrow · open ballot" }
            if days <= 14 { return "Election in \(days) days · prep your ballot" }
            return "Voter Hub · \(days) days to next vote"
        }
        return "Voter Hub"
    }

    @ViewBuilder
    private var lifeEventTile: some View {
        Button {
            Haptics.selection()
            showLifeEvent = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [CivicTheme.violet, CivicTheme.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)
                .shadow(color: CivicTheme.violet.opacity(0.30), radius: 8, x: 0, y: 3)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(lifeEventTileTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        if store.lifeEventPlans.isEmpty {
                            Text("NEW")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(CivicTheme.violet, in: Capsule())
                        }
                    }
                    Text(lifeEventTileSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [CivicTheme.violet.opacity(0.06), CivicTheme.cyan.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.violet.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var lifeEventTileTitle: String {
        if store.lifeEventPlans.isEmpty {
            return "Tell Athen what's going on"
        }
        return "Life-event plans · \(store.lifeEventPlans.count)"
    }

    private var lifeEventTileSubtitle: String {
        if store.lifeEventPlans.isEmpty {
            return "Layoff, baby, move, new business? Get a tailored civic + benefits plan in 10 seconds."
        }
        if let recent = store.lifeEventPlans.first {
            return "Last: \(recent.situation)"
        }
        return "Layoff, baby, move, new business? Get a tailored civic + benefits plan in 10 seconds."
    }

    @ViewBuilder
    private var directoryTile: some View {
        Button {
            Haptics.selection()
            showDirectory = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(CivicTheme.cyan.opacity(0.16))
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CivicTheme.cyan)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(directoryTileTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        if store.federalDirectory.isEmpty {
                            Text("NEW")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(CivicTheme.cyan, in: Capsule())
                        }
                    }
                    Text(directoryTileSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CivicTheme.cyan.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.cyan.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var directoryTileTitle: String {
        let myCount = store.myReps.count
        if myCount > 0 { return "My reps · \(myCount)" }
        return "Browse every elected official"
    }

    private var directoryTileSubtitle: String {
        let fedCount = store.federalDirectory.count
        if fedCount > 0 {
            return "President, Congress, your governor, state reps — with socials, contact info, and votes."
        }
        return "President, Congress, governors, state legislators — searchable directory."
    }

    private var voterHubSubtitle: String {
        if store.isElectionDay {
            return "Polling place, hours, sample ballot — open now."
        }
        if let count = store.sampleBallotResponse?.ballot?.contests.count, count > 0 {
            return "Sample ballot ready with \(count) item\(count == 1 ? "" : "s"). Plus polling, registration, and rep scorecard."
        }
        return "Sample ballot, polling place, registration, and rep scorecard — all in one place."
    }

    // MARK: - Today's briefs rail

    @ViewBuilder
    private var todaysBriefsRail: some View {
        let items = (store.briefDigest?.items ?? []).filter { $0.brief != nil }.prefix(3)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                    Text("TODAY'S BRIEFS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                        .tracking(0.5)
                    Spacer()
                    Button {
                        Haptics.selection()
                        path.append(HomeRoute.issues)
                    } label: {
                        HStack(spacing: 4) {
                            Text("See all")
                                .font(.system(size: 12, weight: .bold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(CivicTheme.violet)
                    }
                    .buttonStyle(.plain)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(items)) { item in
                            Button {
                                Haptics.selection()
                                presentedBrief = item
                            } label: {
                                briefMiniCard(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private func briefMiniCard(_ item: CivicBriefDigestItem) -> some View {
        let brief = item.brief
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: scopeIcon(for: item.issue.scope))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(scopeTint(for: item.issue.scope))
                Text(item.issue.scope.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(scopeTint(for: item.issue.scope))
                    .tracking(0.4)
                Spacer(minLength: 0)
                if let label = brief?.confidence.label {
                    Text(label.display)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(label.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(label.tint.opacity(0.12), in: Capsule())
                }
            }
            Text(brief?.headline ?? item.issue.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(brief?.subhead ?? item.issue.summary)
                .font(.system(size: 12))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(14)
        .frame(width: 250, height: 200, alignment: .topLeading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.hairline, lineWidth: 1))
        .shadow(color: CivicTheme.cardShadow, radius: 10, x: 0, y: 4)
    }

    private func scopeIcon(for scope: String) -> String {
        switch scope {
        case "federal": "building.columns.fill"
        case "state": "flag.fill"
        case "local-philly": "building.2.fill"
        default: "globe.americas.fill"
        }
    }

    private func scopeTint(for scope: String) -> Color {
        switch scope {
        case "federal": CivicTheme.cyan
        case "state": CivicTheme.violet
        case "local-philly": CivicTheme.amber
        default: CivicTheme.mutedInk
        }
    }

    enum HomeRoute: Hashable { case groups, issues }

    // MARK: - View switcher

    private var homeModeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(HomeMode.allCases) { mode in
                let active = homeMode == mode
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        homeMode = mode
                    }
                    if mode == .news && newsItems.isEmpty { Task { await loadNews() } }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12, weight: .bold))
                        Text(mode.label)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(active ? .white : CivicTheme.mutedInk)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(
                        Group {
                            if active { Capsule().fill(mode.tint) } else { Color.clear }
                        }
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.label) view")
            }
        }
        .padding(4)
        .background(CivicTheme.panelElevated, in: Capsule())
        .overlay(Capsule().stroke(CivicTheme.hairline, lineWidth: 1))
    }

    // MARK: - Today mode (existing personalized Home content)

    @ViewBuilder
    private var todayModeContent: some View {
        // AnyView-erase each cluster so the parent only sees three uniform
        // `AnyView` types instead of a deeply nested TupleView<...> chain
        // that crashes the Swift runtime metadata loader on launch
        // (KERN_PROTECTION_FAILURE / stack guard).
        AnyView(todayContentTopCluster)
        AnyView(todayContentMidCluster)
        AnyView(todayContentBottomCluster)
    }

    @ViewBuilder
    private var todayContentTopCluster: some View {
        if shouldPromptPersonalization {
            personalizationPromptCard
        }
        if !store.radarInsights.isEmpty {
            homeCommandCenterCard
        }
        globalSearchBar
        // Audio brief promoted above the hero — strongest daily-habit hook.
        AudioBriefCard()
        dailyBriefHero
        quickActionsRow
        if hasMeaningfulRecap {
            whatIMissedCard
        }
        // ActivityTickerCard + WhatChangedCard moved exclusively to Pulse
        // tab to remove duplication and let each tab have a distinct angle.
    }

    private var homeCommandCenterCard: some View {
        CivicGlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Start here", systemImage: "target")
                        Text("What needs your attention")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                    }
                    Spacer()
                    Button {
                        Haptics.selection()
                        selectTab(.radar)
                    } label: {
                        RectBadge(text: "Radar", systemImage: "dot.radiowaves.left.and.right", tint: CivicTheme.cyan)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 8) {
                    ForEach(Array(store.radarInsights.prefix(3).enumerated()), id: \.element.id) { index, insight in
                        NavigationLink(value: insight.issue.id) {
                            homeCommandRow(index: index, insight: insight)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    Haptics.selection()
                    store.queueAssistantPrompt(homePlanPrompt)
                    selectTab(.assistant)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                        Text("Make a 10-minute plan")
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(CivicTheme.violet)
                    .padding(12)
                    .background(CivicTheme.violet.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func homeCommandRow(index: Int, insight: CivicRadarInsight) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(insight.priority.tint, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(insight.issue.actionTimeEstimate(alreadySent: store.status(for: insight.issue).isSent))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(insight.priority.tint)
                    Text("·")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CivicTheme.quietInk)
                    Text(insight.issue.civicLoopStep(alreadySent: store.status(for: insight.issue).isSent))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CivicTheme.green)
                }
                Text(insight.issue.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .lineLimit(2)
                Text(insight.reason)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
                .padding(.top, 5)
        }
        .padding(10)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 12))
    }

    private var homePlanPrompt: String {
        let items = store.radarInsights.prefix(3).map {
            "- \($0.issue.title): \($0.reason) Recommended action: \($0.recommendedAction)"
        }.joined(separator: "\n")
        return """
        Make me a 10-minute civic plan for today.
        My location: \(store.profile?.displayLocation ?? "not set")
        Top radar items:
        \(items)
        Prioritize what is urgent, what affects me personally, and what is okay to ignore for now.
        """
    }

    @ViewBuilder
    private var todayContentMidCluster: some View {
        if store.hasRecentFollowUps {
            filingFollowUpsCard
        }
        if shouldShowRadar, let insight = store.topRadarInsight {
            NavigationLink(value: insight.issue.id) {
                CivicRadarHeroCard(
                    insight: insight,
                    readyCount: store.readyToActCount,
                    dueSoonCount: store.dueSoonCount,
                    followUpCount: store.followUpCount,
                )
            }
            .buttonStyle(.plain)
        }
        if !deadlineItems.isEmpty {
            DeadlineRailCard(items: deadlineItems)
        }
        todaysBriefsRail
        if let cohortItem = bestCohortItem, let brief = cohortItem.brief {
            CohortCard(brief: brief, profile: store.profile, issue: cohortItem.issue)
        }
        if !store.visibleIssues.isEmpty {
            nextMovesBlock
        }
    }

    @ViewBuilder
    private var todayContentBottomCluster: some View {
        // "More to explore" — secondary cards, visually de-emphasized so
        // users know they're below-the-fold extras rather than core actions.
        // nextVoteCard removed — fully covered by the Pulse vote-scheduled
        // event row, no need to render the same thing twice.
        if shouldShowFederalCard
            || shouldShowSourcePulse
            || BetaFeatures.outreachGroups || !store.groups.isEmpty
            || showAllCaughtUp {
            moreToExploreHeader
        }
        if shouldShowFederalCard, let issue = topFederalIssue {
            topFederalCard(issue: issue)
        }
        if shouldShowSourcePulse {
            sourcePulseCard
        }
        if BetaFeatures.outreachGroups || !store.groups.isEmpty {
            crewTile
        }
        if showAllCaughtUp {
            allCaughtUpCard
        }
        // "See all items" moved into the radar hero card at the top of
        // Today so users don't have to scroll to the bottom of Home.
    }

    // MARK: - News mode (free-source headlines)

    @ViewBuilder
    private var newsModeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            newsHeaderCard
            if let summary = newsSummary, !summary.isEmpty {
                newsSummaryCard(summary)
            } else if newsIsLoading && newsSummary == nil && !newsItems.isEmpty {
                newsSummaryLoadingCard
            }
            if newsIsLoading && newsItems.isEmpty {
                newsLoadingSkeleton
            } else if let err = newsError {
                newsErrorCard(err)
            } else if newsItems.isEmpty {
                newsEmptyCard
            } else {
                ForEach(newsItems) { item in
                    NewsHeadlineCard(headline: item) {
                        if let url = URL(string: item.link) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Text("Headlines via Google News · summary via Claude · refreshed every 30 min")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CivicTheme.quietInk)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
        }
        .task {
            // Only fetch on first visit ever (cache is empty). After that,
            // News content is "sticky" — switching tabs / closing the app
            // doesn't trigger a refetch. Reload button is the only way.
            if newsItems.isEmpty && !newsIsLoading { await loadNews() }
        }
    }

    /// "Quick glance" 2-3 sentence summary at the top of News mode.
    /// Powered by Claude on the backend, cached alongside the headlines.
    private func newsSummaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CivicTheme.violet)
                Text("QUICK GLANCE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(CivicTheme.violet)
                Spacer()
                AIDisclosureChip(surface: .brief, compact: true)
            }
            Text(summary)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CivicTheme.ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [CivicTheme.violet.opacity(0.08), CivicTheme.cyan.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            ),
            in: RoundedRectangle(cornerRadius: 14),
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.violet.opacity(0.20), lineWidth: 1))
    }

    private var newsSummaryLoadingCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(CivicTheme.violet).scaleEffect(0.85)
            Text("Writing your quick glance…")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.violet.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private var newsHeaderCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CivicTheme.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("Local + national news")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text("What the press is writing about \(store.profile?.localityLabel ?? store.profile?.stateName ?? "your area")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
            }
            Spacer()
            Button {
                Haptics.selection()
                // Always bump the spin angle so each tap visibly rotates
                // the icon — even when the response comes back cached and
                // the spinner state never flips long enough to animate.
                withAnimation(.easeOut(duration: 0.4)) {
                    newsSpinAngle += 360
                }
                Task { await loadNews(force: true) }
            } label: {
                ZStack {
                    if newsIsLoading {
                        ProgressView()
                            .tint(CivicTheme.cyan)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CivicTheme.cyan)
                            .rotationEffect(.degrees(newsSpinAngle))
                    }
                }
                .frame(width: 32, height: 32)
                .background(CivicTheme.cyan.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(CivicTheme.cyan.opacity(0.20), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(newsIsLoading)
            .accessibilityLabel(newsIsLoading ? "Loading news" : "Refresh news")
        }
        .padding(14)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private var newsLoadingSkeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6).fill(CivicTheme.hairline).frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(CivicTheme.hairline.opacity(0.7)).frame(height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(CivicTheme.hairline.opacity(0.5)).frame(width: 180, height: 10)
                    }
                    Spacer()
                }
                .padding(12)
                .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
                .redacted(reason: .placeholder)
            }
        }
    }

    private func newsErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(CivicTheme.amber)
                Text("Couldn't fetch headlines").font(.system(size: 14, weight: .bold))
            }
            Text(message).font(.system(size: 12, weight: .medium)).foregroundStyle(CivicTheme.mutedInk)
            Button { Task { await loadNews(force: true) } } label: {
                Text("Try again").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(CivicTheme.cyan, in: Capsule())
            }.buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.amber.opacity(0.18), lineWidth: 1))
    }

    private var newsEmptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "newspaper").font(.system(size: 32, weight: .light)).foregroundStyle(CivicTheme.quietInk)
            Text("No headlines yet").font(.system(size: 14, weight: .bold)).foregroundStyle(CivicTheme.ink)
            Text("Tap refresh to fetch the latest.").font(.system(size: 12)).foregroundStyle(CivicTheme.mutedInk)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    private func loadNews(force: Bool = false) async {
        guard !newsIsLoading else { return }
        guard let baseURL = store.effectiveBackendURL else {
            newsError = "Demo mode — no backend configured for News."
            return
        }
        newsIsLoading = true
        if force { newsSummary = nil }
        defer { newsIsLoading = false }
        let service = NewsService(baseURL: baseURL)
        do {
            let feed = try await service.fetchNews(
                city: store.profile?.localityLabel,
                state: store.profile?.stateName,
                force: force,
                includeSummary: true,
            )
            newsItems = feed.items
            newsSummary = feed.summary
            newsError = nil
            // Persist so reopening the app shows the same content until
            // the user explicitly reloads.
            HomeNewsCache.shared.save(items: feed.items, summary: feed.summary)
        } catch {
            newsError = (error as? LocalizedError)?.errorDescription ?? "News fetch failed."
        }
    }

    // MARK: - Pulse mode (live civic activity)

    @ViewBuilder
    private var pulseModeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            PulseFeedView { issueID in
                path.append(issueID)
            }
            pulseFooterTip
        }
    }

    private var pulseFooterTip: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
            Text("Pulse refreshes silently every 10 min when you reopen the app.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CivicTheme.quietInk)
        }
        .padding(.top, 4)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(greeting)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .textCase(.uppercase)
                Text(headlineForProfile)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if store.profile != nil {
                    Text(lastRefreshLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.quietInk)
                        .textCase(.uppercase)
                        .tracking(0.4)
                }
            }
            if store.profile != nil {
                Spacer(minLength: 8)
                inboxButton
                refreshButton
            }
        }
    }

    private var inboxButton: some View {
        Button {
            Haptics.selection()
            showInbox = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(CivicTheme.panel)
                    .overlay(Circle().stroke(CivicTheme.hairline, lineWidth: 1))
                    .frame(width: 40, height: 40)
                Image(systemName: "bell.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .frame(width: 40, height: 40)
                if store.unreadInboxCount > 0 {
                    Text(badgeText(store.unreadInboxCount))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(CivicTheme.red, in: Capsule())
                        .offset(x: 4, y: -4)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Notifications, \(store.unreadInboxCount) unread")
    }

    private func badgeText(_ count: Int) -> String {
        count > 9 ? "9+" : "\(count)"
    }

    private var refreshButton: some View {
        Button {
            Haptics.selection()
            startStreamingRefresh()
        } label: {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(CivicTheme.cyan.opacity(0.14))
                    Circle()
                        .stroke(CivicTheme.cyan.opacity(0.22), lineWidth: 1)
                    if isAnyRefreshActive {
                        ProgressView().tint(CivicTheme.cyan)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(CivicTheme.cyan)
                    }
                }
                .frame(width: 44, height: 44)
                .shadow(color: CivicTheme.cyan.opacity(0.18), radius: 8, x: 0, y: 3)

                if store.isFeedStale && !isAnyRefreshActive {
                    Circle()
                        .fill(CivicTheme.amber)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(CivicTheme.screenBackground, lineWidth: 2))
                        .offset(x: 2, y: -2)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.isFeedStale
                            ? "Refresh civic items — last pulled over 6 hours ago"
                            : "Refresh civic items and sources")
        .disabled(isAnyRefreshActive)
    }

    private var isAnyRefreshActive: Bool {
        store.isRunningOrchestrator || store.isRefreshingIssues || store.isRefreshingSources
    }

    private var lastRefreshLabel: String {
        if store.isRunningOrchestrator {
            return "Pulling fresh sources…"
        }
        if store.isRefreshingIssues || store.isRefreshingSources {
            return "Refreshing…"
        }
        if case .offline = store.backendStatus {
            return "Backend offline"
        }
        if let err = store.lastOrchestratorError {
            return "Last refresh: \(err)"
        }
        if let report = store.lastRefreshReport, report.totalInserted + report.totalUpdated > 0 {
            let label = report.totalInserted == 0
                ? "Updated \(report.totalUpdated) items"
                : "\(report.totalInserted) new · \(report.totalUpdated) updated"
            return label
        }
        if let stamp = store.lastIssueRefreshAt {
            let elapsed = -stamp.timeIntervalSinceNow
            switch elapsed {
            case ..<60: return "Updated just now"
            case ..<3600:
                let minutes = max(1, Int(elapsed / 60))
                return "Updated \(minutes)m ago"
            case ..<86400:
                let hours = max(1, Int(elapsed / 3600))
                return "Updated \(hours)h ago"
            default:
                let days = max(1, Int(elapsed / 86400))
                return "Updated \(days)d ago"
            }
        }
        switch store.settings.refreshInterval {
        case .manualOnly: return "Manual refresh"
        default: return "Auto · \(store.settings.refreshInterval.shortLabel)"
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hello"
        }
    }

    private var headlineForProfile: String {
        guard let profile = store.profile else {
            return "Welcome to \(AppBrand.name)"
        }
        if store.topRadarInsight != nil {
            return "Your daily brief"
        }
        let count = store.visibleIssues.count
        return "\(count) item\(count == 1 ? "" : "s") moving in \(profile.stateName) this week"
    }

    // MARK: - W2 overhaul state

    @State private var searchQuery: String = ""
    @State private var hasTriggeredFirstRun: Bool = false

    /// First-run loading: profile is set but no data yet AND we're refreshing.
    /// Lets us show a full-screen "Athen is fetching your civic feed" rather
    /// than a confusing half-populated Home.
    private var isFirstRunLoading: Bool {
        store.profile != nil
            && store.visibleIssues.isEmpty
            && (store.briefDigest?.items.isEmpty ?? true)
            && (store.isRefreshingIssues || store.isRunningOrchestrator || store.isLoadingBriefDigest)
    }

    /// Hide the pulse strip when all three chips would be empty/zero — looked
    /// like three dashes at the top of a fresh install.
    private var shouldShowPulseStrip: Bool {
        store.civicStreakDays > 0 || !store.diffEvents.isEmpty || nextVoteIssue != nil
    }

    /// Upcoming votes / comment windows in the next 45 days, surfaced as a
    /// horizontal rail. Sourced from the brief digest so the headlines match
    /// what the cards below show.
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
                    voteDate: date,
                )
            }
            .sorted { $0.voteDate < $1.voteDate }
    }

    /// Pick the brief item that best matches the user's profile factors so
    /// the cohort card actually says something specific. Falls back to the
    /// first item with a brief if no factor match is found.
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

    /// Wraps `runFullRefresh()` so the user sees a quick confirmation toast.
    /// Routes through the structured `RefreshOutcome` so we surface
    /// in-flight / rate-limit / failure states honestly instead of a
    /// misleading "you're already up to date" when nothing actually ran.
    private func refreshWithToast() async {
        let outcome = await store.runFullRefresh()
        switch outcome {
        case .ran(let inserted, let updated):
            let message: String
            if inserted == 0 && updated == 0 {
                message = "You're already up to date."
            } else if inserted > 0 && updated > 0 {
                message = "\(inserted) new, \(updated) updated"
            } else if inserted > 0 {
                message = "\(inserted) new item\(inserted == 1 ? "" : "s")"
            } else {
                message = "\(updated) updated"
            }
            showToast(message)
            // If something new actually landed, log an inbox notification so
            // a user who refreshed in passing can find it later.
            if inserted > 0 {
                store.recordInboxNotification(
                    .init(
                        id: "inbox.refresh.\(Int(Date.now.timeIntervalSince1970))",
                        kind: .systemUpdate,
                        title: "\(inserted) new civic item\(inserted == 1 ? "" : "s")",
                        body: "Refreshed from your sources just now.",
                        issueID: nil,
                        scheduledAtISO: ISO8601DateFormatter().string(from: .now),
                        isRead: false,
                    ),
                )
            }
        case .alreadyRunning:
            showToast("Already refreshing — hang tight.")
        case .skippedRecent(let secondsAgo):
            showToast("Already fresh — last pulled \(secondsAgo)s ago.")
        case .failed(let reason):
            showToast(reason.contains("rate") || reason.contains("429")
                ? "Slow down — give the sources a minute."
                : "Refresh hit a snag — pulled what we could.")
        case .mockMode:
            showToast("Demo mode — no live sources to pull.")
        }
    }

    @MainActor
    private func showToast(_ text: String) {
        refreshToast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if refreshToast == text {
                refreshToast = nil
            }
        }
    }

    @ViewBuilder
    private var refreshToastOverlay: some View {
        if let toast = refreshToast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(CivicTheme.cyan)
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: refreshToast)
        }
    }

    @ViewBuilder
    private var refreshDrawerOverlay: some View {
        if refreshDrawerVisible {
            RefreshProgressDrawer(
                startedAt: refreshStreamStartedAt,
                rows: refreshStreamRows,
                summary: refreshStreamSummary,
                errorMessage: refreshStreamError,
                onDismiss: dismissRefreshDrawer,
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 90)  // sit above the tab bar
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: refreshDrawerVisible)
        }
    }

    /// Tap-triggered refresh that opens the live progress drawer. Pull-to-
    /// refresh on Home keeps the simpler `refreshWithToast()` path because
    /// SwiftUI's `.refreshable` doesn't play nicely with a streaming UI.
    private func startStreamingRefresh() {
        guard !store.isRunningOrchestrator else {
            showToast("Already refreshing — hang tight.")
            return
        }
        guard let baseURL = store.effectiveBackendURL else {
            // No backend configured (demo mode) — fall back to toast path.
            Task { await refreshWithToast() }
            return
        }
        // Reset drawer state + show it before kickoff.
        refreshStreamStartedAt = .now
        refreshStreamRows = []
        refreshStreamSummary = nil
        refreshStreamError = nil
        withAnimation { refreshDrawerVisible = true }

        let service = RefreshStreamService(baseURL: baseURL)
        store.isRunningOrchestrator = true
        refreshStreamTask?.cancel()
        // `.detached` so the SSE iteration survives the caller's task
        // ending — critical when fired from inside `.refreshable`'s async
        // closure, which otherwise propagates cancellation here.
        refreshStreamTask = Task.detached(priority: .userInitiated) {
            do {
                for try await event in service.stream() {
                    await MainActor.run { self.handleStreamEvent(event) }
                }
                await MainActor.run { self.store.isRunningOrchestrator = false }
            } catch {
                await MainActor.run {
                    let message = (error as? LocalizedError)?.errorDescription
                        ?? (error.localizedDescription.isEmpty ? "Couldn't reach the backend." : error.localizedDescription)
                    self.refreshStreamError = message
                    self.store.lastOrchestratorError = message
                    self.store.isRunningOrchestrator = false
                    Task { await self.store.checkBackendHealth() }
                }
            }
        }
    }

    @MainActor
    private func handleStreamEvent(_ event: RefreshStreamEvent) {
        switch event {
        case .started(let at):
            refreshStreamStartedAt = at
        case .sourceStarted(let id, let name):
            if !refreshStreamRows.contains(where: { $0.id == id }) {
                refreshStreamRows.append(.init(id: id, name: name, status: .running))
            }
        case .sourceDone(let report):
            if let idx = refreshStreamRows.firstIndex(where: { $0.id == report.id }) {
                refreshStreamRows[idx].status = mapStatus(report.status, error: report.error, skipped: report.skippedReason)
                refreshStreamRows[idx].inspected = report.inspected
                refreshStreamRows[idx].inserted = report.inserted
                refreshStreamRows[idx].updated = report.updated
                refreshStreamRows[idx].errorMessage = report.error
            }
        case .complete(let report):
            // Sync the store's report + bump the last-completed timestamp so
            // the stale-badge clears and the smart-cooldown re-arms.
            store.lastRefreshReport = report
            store.lastRefreshCompletedAt = .now
            refreshStreamSummary = .init(
                totalInserted: report.totalInserted,
                totalUpdated: report.totalUpdated,
                totalIssues: report.totalIssues,
                durationMs: report.durationMs,
            )
            // Refresh the local cached issues + sources lists so the rest of
            // Home reflects the new data immediately.
            Task {
                async let issuesLoaded = store.refreshIssues()
                async let sourcesLoaded = store.refreshSources()
                _ = await (issuesLoaded, sourcesLoaded)
            }
            if report.totalInserted > 0 {
                Haptics.success()
                store.recordInboxNotification(
                    .init(
                        id: "inbox.refresh.\(Int(Date.now.timeIntervalSince1970))",
                        kind: .systemUpdate,
                        title: "\(report.totalInserted) new civic item\(report.totalInserted == 1 ? "" : "s")",
                        body: "Refreshed from your sources just now.",
                        issueID: nil,
                        scheduledAtISO: ISO8601DateFormatter().string(from: .now),
                        isRead: false,
                    ),
                )
            }
        case .failed(let msg):
            refreshStreamError = msg
            store.lastOrchestratorError = msg
            Task {
                await store.refreshIssues()
                await store.refreshSources()
            }
        }
    }

    private func mapStatus(_ status: String, error: String?, skipped: String?) -> RefreshProgressDrawer.Row.Status {
        switch status {
        case "ok": return .ok
        case "skipped": return .skipped(skipped)
        case "failed": return .failed
        default: return .running
        }
    }

    private func dismissRefreshDrawer() {
        refreshStreamTask?.cancel()
        refreshStreamTask = nil
        withAnimation { refreshDrawerVisible = false }
    }

    /// Surface the personalization prompt when the user finished onboarding
    /// but never picked interests or factors. Without these the daily brief
    /// is generic; with one of them it gets noticeably more useful.
    private var shouldPromptPersonalization: Bool {
        guard let profile = store.profile else { return false }
        return profile.interests.isEmpty && profile.factors.isEmpty
    }

    private var personalizationPromptCard: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CivicTheme.violet)
                    Text("Tailor your daily brief")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Spacer()
                }
                Text("Tell Athen what you care about and a few things about your life. We'll prioritize bills that actually affect you.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        Haptics.selection()
                        showTopicsPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checklist")
                                .font(.system(size: 12, weight: .bold))
                            Text("Pick topics")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(CivicTheme.violet, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.selection()
                        showContextPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 12, weight: .bold))
                            Text("Add context")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(Capsule().stroke(CivicTheme.violet.opacity(0.6), lineWidth: 1))
                        .foregroundStyle(CivicTheme.violet)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
        }
    }

    /// Show the "all caught up" celebration when the feed has loaded but the
    /// user has nothing pending (no readyToAct, no upcoming votes within 7d).
    private var showAllCaughtUp: Bool {
        guard !store.visibleIssues.isEmpty else { return false }
        guard store.readyToActCount == 0 else { return false }
        guard store.dueSoonCount == 0 else { return false }
        return true
    }

    private var firstRunLoadingState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 40)
            ZStack {
                Circle().fill(CivicTheme.cyan.opacity(0.16))
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
            }
            .frame(width: 84, height: 84)
            VStack(spacing: 8) {
                Text("Fetching civic data for \(briefLocation)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                Text("Bills, votes, elections, and your reps. Takes about 10 seconds.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CivicTheme.mutedInk)
                    .padding(.horizontal, 32)
            }
            ProgressView().tint(CivicTheme.cyan)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    @ViewBuilder
    private var electionDayBanner: some View {
        if let next = store.nextElection, next.isToday {
            Button {
                selectTab(.vote)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.white)
                        Text("ELECTION DAY")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(.white)
                    }
                    Text(next.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Tap to open Vote — polling place, sample ballot, and your rep scorecard are ready.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineSpacing(2)
                    HStack {
                        Text("Open Vote")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CivicTheme.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(.white, in: Capsule())
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [CivicTheme.red, Color(red: 0.55, green: 0.10, blue: 0.30)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18)
                )
                .shadow(color: CivicTheme.red.opacity(0.35), radius: 14, x: 0, y: 5)
            }
            .buttonStyle(.plain)
        }
    }

    private var globalSearchBar: some View {
        GlobalSearchBar(
            text: $searchQuery,
            onSubmit: {
                let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Haptics.selection()
                store.queueAssistantPrompt(trimmed)
                searchQuery = ""
                selectTab(.assistant)
            }
        )
    }

    /// Single horizontal strip replacing the four vertical tiles. Voter Hub
    /// is now a top-level tab so it's not here.
    private var quickActionsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("QUICK ACTIONS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .tracking(0.6)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    quickActionChip(title: "Tell Athen", subtitle: "Life events", icon: "sparkles.rectangle.stack.fill", tint: CivicTheme.violet) {
                        showLifeEvent = true
                    }
                    quickActionChip(title: "Petitions", subtitle: petitionsBadge, icon: "person.3.sequence.fill", tint: CivicTheme.cyan) {
                        showPetitions = true
                    }
                    quickActionChip(title: "Reps", subtitle: "Directory", icon: "person.text.rectangle.fill", tint: CivicTheme.amber) {
                        showDirectory = true
                    }
                    quickActionChip(title: "Get help", subtitle: "Services + benefits", icon: "heart.text.square.fill", tint: CivicTheme.green) {
                        showingHelp = true
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var petitionsBadge: String {
        let open = store.petitions.filter { $0.status == .open }.count
        return open == 0 ? "Start one" : "\(open) open"
    }

    private func quickActionChip(title: String, subtitle: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.15))
                    Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(tint)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(CivicTheme.ink)
                    Text(subtitle).font(.system(size: 10, weight: .semibold)).foregroundStyle(CivicTheme.mutedInk).lineLimit(1)
                }
            }
            .padding(12)
            .frame(width: 130, alignment: .leading)
            .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// "What I missed" — true only when the user has been away long enough
    /// for new things to have happened AND there are actually new things.
    /// Stops the recap from showing every app open.
    private var hasMeaningfulRecap: Bool {
        guard let last = store.previousLastOpenedAt else { return false }
        guard Date.now.timeIntervalSince(last) > 12 * 3600 else { return false }
        return recapDiffCount + recapFollowUpCount + recapNewIssueCount > 0
    }

    private var recapDiffCount: Int { store.diffEvents.count }
    private var recapFollowUpCount: Int { store.recentFilingFollowUps.count }
    private var recapNewIssueCount: Int {
        guard let last = store.previousLastOpenedAt else { return 0 }
        // Proxy for "new to user": issues with upcoming votes added since
        // last open. Without a true ingestedAt, this favors upcoming-deadline
        // urgency over absolute novelty — which is the right tradeoff.
        return store.visibleIssues.filter { $0.voteDate > last && !$0.hasVotePassed }.count
    }

    private var whatIMissedCard: some View {
        let total = recapDiffCount + recapFollowUpCount + recapNewIssueCount
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
                Text("WHAT YOU MISSED")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(CivicTheme.cyan)
                Spacer()
                Text("\(total)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
                    .monospacedDigit()
            }
            HStack(spacing: 14) {
                if recapNewIssueCount > 0 {
                    recapStat(value: recapNewIssueCount, label: "new items")
                }
                if recapDiffCount > 0 {
                    recapStat(value: recapDiffCount, label: "changes")
                }
                if recapFollowUpCount > 0 {
                    recapStat(value: recapFollowUpCount, label: "vote results")
                }
            }
        }
        .padding(14)
        .background(CivicTheme.cyan.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.cyan.opacity(0.20), lineWidth: 1))
    }

    private func recapStat(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .textCase(.uppercase)
        }
    }

    private var filingFollowUpsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.badge.questionmark.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.violet)
                Text("UPDATES ON YOUR FILINGS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(CivicTheme.violet)
                Spacer()
            }
            VStack(spacing: 8) {
                ForEach(store.recentFilingFollowUps.prefix(3)) { followUp in
                    Button {
                        Haptics.selection()
                        if let uuid = UUID(uuidString: followUp.issueId) {
                            path.append(uuid)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle().fill((followUp.aligned ? CivicTheme.green : CivicTheme.amber).opacity(0.18))
                                Image(systemName: followUp.aligned ? "checkmark" : "exclamationmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(followUp.aligned ? CivicTheme.green : CivicTheme.amber)
                            }
                            .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(followUp.issueTitle)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(CivicTheme.ink)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 6) {
                                    Text("\(followUp.officialName) voted \(followUp.officialVote.uppercased())")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(CivicTheme.mutedInk)
                                    Text("·")
                                        .foregroundStyle(CivicTheme.quietInk)
                                    Text(followUp.aligned ? "ALIGNED" : "MISMATCH")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(0.4)
                                        .foregroundStyle(followUp.aligned ? CivicTheme.green : CivicTheme.amber)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(CivicTheme.quietInk)
                        }
                        .padding(12)
                        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(CivicTheme.violet.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.violet.opacity(0.18), lineWidth: 1))
    }

    private var moreToExploreHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
            Text("MORE TO EXPLORE")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(CivicTheme.quietInk)
            Spacer()
        }
        .padding(.top, 6)
    }

    private var allCaughtUpCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(CivicTheme.green.opacity(0.18))
                Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(CivicTheme.green)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("You're all caught up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text("Nothing pending. Pull to refresh — or wait for the next deadline to surface.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.green.opacity(0.22), lineWidth: 1))
    }

    @ViewBuilder
    private var lastRefreshFooter: some View {
        if let timestamp = lastRefreshTimestamp {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                Text("Last refresh \(timestamp)")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(CivicTheme.quietInk)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
    }

    private var lastRefreshTimestamp: String? {
        guard let date = store.lastIssueRefreshAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private var zipPromptCard: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Set your ZIP", systemImage: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.cyan)
                Text("Tell us where you live. We use your ZIP to find your federal, state, and local representatives — and to translate civic items that actually affect you.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
                Button {
                    showProfileSheet = true
                } label: {
                    HStack {
                        Text("Enter ZIP")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(CivicTheme.cyan.opacity(0.18), in: RoundedRectangle(cornerRadius: CivicTheme.cornerRadius))
                    .foregroundStyle(CivicTheme.cyan)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dailyBriefHero: some View {
        CivicGlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("\(heroLabelPrefix) \(briefLocation)", systemImage: heroIcon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Text(briefHeadline)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 10)

                    VStack(alignment: .trailing, spacing: 5) {
                        Text(sourceFreshnessLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.18), in: Capsule())
                        if hasTrustData {
                            Text(trustSummary)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.82))
                                .monospacedDigit()
                        }
                    }
                }
                .padding(18)
                .background(heroGradient)

                VStack(alignment: .leading, spacing: 15) {
                    Text(briefSummary)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(CivicTheme.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        briefMetric("\(activeIssueCount)", "Active", CivicTheme.cyan)
                        briefMetric("\(urgentIssueCount)", "Urgent", CivicTheme.amber)
                        briefMetric("\(store.matchedServices.count)", "Help", CivicTheme.green)
                    }

                    // "See all items" — surfaced here in the time-of-day
                    // hero so users can jump to the full issue list without
                    // hunting at the bottom of Home.
                    Button {
                        Haptics.selection()
                        path.append(HomeRoute.issues)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "list.bullet.rectangle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(CivicTheme.cyan)
                            Text("See all items")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(CivicTheme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(CivicTheme.quietInk)
                        }
                        .padding(13)
                        .background(CivicTheme.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                        .overlay(RoundedRectangle(cornerRadius: CivicTheme.mediumRadius).stroke(CivicTheme.cyan.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.selection()
                        handleHeroCTA()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: heroCTAIcon)
                                .font(.system(size: 14, weight: .bold))
                            Text(heroCTALabel)
                                .font(.system(size: 14, weight: .bold))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(CivicTheme.ink)
                        .padding(13)
                        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                    }
                    .buttonStyle(.plain)

                    // Audio briefing button removed — AudioBriefCard sits
                    // directly below this hero so a duplicate CTA was redundant.
                    if false {
                        Button {} label: {
                            HStack(spacing: 8) {
                                Image(systemName: "headphones")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Play audio briefing")
                                    .font(.system(size: 13, weight: .bold))
                                Spacer()
                                Image(systemName: "play.fill")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(CivicTheme.cyan)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 11)
                            .background(CivicTheme.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                            .overlay(RoundedRectangle(cornerRadius: CivicTheme.mediumRadius).stroke(CivicTheme.cyan.opacity(0.20), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
        }
    }

    private func briefMetric(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
    }

    private var nextMovesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Next moves", systemImage: "checklist.checked")
                .padding(.horizontal, 2)

            VStack(spacing: 10) {
                ForEach(Array(homeActions.prefix(3))) { action in
                    homeActionRow(action)
                }
            }
        }
    }

    @ViewBuilder
    private func homeActionRow(_ action: HomeActionItem) -> some View {
        if let issueID = action.issueID, store.issue(with: issueID) != nil {
            NavigationLink(value: issueID) {
                homeActionContent(action)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                handle(action)
            } label: {
                homeActionContent(action)
            }
            .buttonStyle(.plain)
        }
    }

    private func homeActionContent(_ action: HomeActionItem) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                    .fill(action.tint.opacity(0.14))
                Image(systemName: action.systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(action.tint)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(action.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                Text(action.detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(action.cta)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(action.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: CivicTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: CivicTheme.cornerRadius)
                .stroke(CivicTheme.hairline, lineWidth: 1)
        }
        .shadow(color: CivicTheme.cardShadow, radius: 12, x: 0, y: 5)
    }

    private func handle(_ action: HomeActionItem) {
        Haptics.selection()
        switch action.kind {
        case .issue:
            selectTab(.home)
        case .service:
            showingHelp = true
        case .assistant:
            store.queueAssistantPrompt("Give me a practical plan for today based on my civic deadlines, public-service matches, and reps. Keep it short and tell me exactly what to do first.")
            selectTab(.assistant)
        case .refresh:
            startStreamingRefresh()
        case .feed:
            selectTab(.square)
        }
    }

    private func refreshErrorCard(_ error: String) -> some View {
        CivicGlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CivicTheme.amber)
                    .frame(width: 34, height: 34)
                    .background(CivicTheme.amber.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text("Live refresh needs attention")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Text(error)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Haptics.selection()
                        startStreamingRefresh()
                    } label: {
                        Text("Try again")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CivicTheme.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var helpTile: some View {
        Button {
            Haptics.selection()
            showingHelp = true
        } label: {
            CivicGlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                            .fill(CivicTheme.green.opacity(0.15))
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(CivicTheme.green)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(helpTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        Text(helpSubtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CivicTheme.quietInk)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var sourcePulseCard: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    SectionHeader(title: "Source pulse", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    RectBadge(text: sourceFreshnessLabel, systemImage: "checkmark.shield.fill", tint: sourcePulseTint)
                }

                Text(sourcePulseCopy)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    sourceMetric("\(registeredSourceCount)", "Sources", CivicTheme.cyan)
                    sourceMetric("\(activeSourceHostCount)", "Active hosts", CivicTheme.violet)
                    sourceMetric(averageTrustDisplay, "Trust", CivicTheme.green)
                }
            }
        }
    }

    private func sourceMetric(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
    }

    private var helpTitle: String {
        let needs = store.profile?.serviceNeeds.count ?? 0
        return needs == 0 ? "Find public services" : "\(store.matchedServices.count) service matches"
    }

    private var helpSubtitle: String {
        if let need = store.profile?.serviceNeeds.first {
            return "Start with \(need.label.lowercased()), benefits, documents, and next steps"
        }
        return "Housing, food, health, transit, legal aid, jobs, and records"
    }

    private var briefLocation: String {
        if let location = store.civicBrief?.locationLabel, !location.isEmpty {
            return location
        }
        return store.profile?.displayLocation ?? "your area"
    }

    private var briefHeadline: String {
        if let headline = store.civicBrief?.headline, !headline.isEmpty {
            return headline
        }
        if let insight = store.topRadarInsight {
            return "\(insight.issue.voteCountdownLabel) left on the top item"
        }
        if store.isRefreshingIssues || store.isRunningOrchestrator {
            return "Loading your civic feed…"
        }
        return "Pull down to load your civic feed"
    }

    private var briefSummary: String {
        if let summary = store.civicBrief?.summary, !summary.isEmpty {
            return summary
        }
        if let insight = store.topRadarInsight {
            return "\(insight.issue.title): \(insight.reason) \(insight.recommendedAction)."
        }
        if store.isRefreshingIssues || store.isRunningOrchestrator {
            return "Athen is fetching bills, votes, and deadlines for \(briefLocation). One moment…"
        }
        if store.visibleIssues.isEmpty {
            return "No civic items loaded yet for \(briefLocation). Pull to refresh, or check the Sources panel."
        }
        return "\(store.visibleIssues.count) items are ready to review across your area."
    }

    private var activeIssueCount: Int {
        store.civicBrief?.metrics.activeIssues ?? store.visibleIssues.filter { !$0.hasVotePassed }.count
    }

    private var urgentIssueCount: Int {
        store.civicBrief?.metrics.urgentIssues ?? store.dueSoonCount
    }

    private var trustSummary: String {
        guard let average = store.civicBrief?.sourceHealth.averageTrustScore ?? localAverageTrust else {
            return "Loading sources"
        }
        return "\(average)% trust"
    }

    private var hasTrustData: Bool {
        (store.civicBrief?.sourceHealth.averageTrustScore ?? localAverageTrust) != nil
    }

    private var averageTrustDisplay: String {
        guard let average = store.civicBrief?.sourceHealth.averageTrustScore ?? localAverageTrust else {
            return "—"
        }
        return "\(average)%"
    }

    private var localAverageTrust: Int? {
        let issues = store.visibleIssues
        guard !issues.isEmpty else { return nil }
        let total = issues.reduce(0) { $0 + $1.trustScore }
        return Int((Double(total) / Double(issues.count)).rounded())
    }

    private var sourceFreshnessLabel: String {
        if let label = store.civicBrief?.sourceHealth.freshnessLabel, !label.isEmpty {
            return label
        }
        if store.lastIssueRefreshAt != nil {
            return "Updated now"
        }
        return "Ready"
    }

    private var sourcePulseTint: Color {
        switch sourceFreshnessLabel {
        case "Fresh", "Updated today", "Updated now":
            return CivicTheme.green
        case "Ready":
            return CivicTheme.cyan
        default:
            return CivicTheme.amber
        }
    }

    private var sourcePulseCopy: String {
        if let health = store.civicBrief?.sourceHealth {
            let sourceCount = health.registeredSources.map(String.init) ?? "\(activeSourceHostCount)"
            return "\(sourceCount) registered sources, \(health.activeSourceHosts) active hosts, and \(averageTrustDisplay) average trust. Last backend update: \(health.freshnessLabel.lowercased())."
        }
        return "Athen is ready to pull live civic items once the backend source mesh is connected."
    }

    private var registeredSourceCount: Int {
        store.civicBrief?.sourceHealth.registeredSources ?? activeSourceHostCount
    }

    private var activeSourceHostCount: Int {
        if let count = store.civicBrief?.sourceHealth.activeSourceHosts {
            return count
        }
        let hosts = store.visibleIssues.compactMap { issue -> String? in
            if let host = issue.sourceHost, !host.isEmpty { return host }
            return issue.sourceURLValue?.host?.replacingOccurrences(of: "www.", with: "")
        }
        return max(1, Set(hosts).count)
    }

    private var homeActions: [HomeActionItem] {
        if let backendActions = store.civicBrief?.actions, !backendActions.isEmpty {
            return backendActions
                .sorted { $0.priority < $1.priority }
                .map(actionFromBackend)
        }

        var actions: [HomeActionItem] = []
        if let insight = store.topRadarInsight {
            actions.append(
                HomeActionItem(
                    id: "top-issue-\(insight.issue.id.uuidString)",
                    kind: .issue,
                    title: insight.recommendedAction,
                    detail: insight.issue.title,
                    cta: "Open",
                    systemImage: insight.priority.systemImage,
                    tint: insight.priority.tint,
                    issueID: insight.issue.id
                )
            )
        }
        if let service = store.matchedServices.first {
            actions.append(
                HomeActionItem(
                    id: "top-service-\(service.id.uuidString)",
                    kind: .service,
                    title: "Check your best help match",
                    detail: "\(service.title) · \(service.matchScore(for: store.profile))% fit",
                    cta: "Help",
                    systemImage: service.category.systemImage,
                    tint: service.category.tint,
                    issueID: nil
                )
            )
        }
        actions.append(
            HomeActionItem(
                id: "ask-plan",
                kind: .assistant,
                title: "Ask Athen for the short version",
                detail: "Get a plain-English plan for deadlines, services, and who to contact.",
                cta: "Ask",
                systemImage: "sparkles",
                tint: CivicTheme.violet,
                issueID: nil
            )
        )
        if actions.count < 3 {
            actions.append(
                HomeActionItem(
                    id: "refresh-live",
                    kind: .refresh,
                    title: "Refresh live sources",
                    detail: "Pull the latest backend issue sweep when your API is connected.",
                    cta: "Refresh",
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: CivicTheme.cyan,
                    issueID: nil
                )
            )
        }
        return actions
    }

    private func actionFromBackend(_ action: CivicBrief.Action) -> HomeActionItem {
        let kind = HomeActionKind(rawValue: action.kind) ?? .assistant
        return HomeActionItem(
            id: action.id,
            kind: kind,
            title: action.title,
            detail: action.detail,
            cta: action.cta,
            systemImage: action.systemImage,
            tint: tint(for: kind),
            issueID: action.issueID
        )
    }

    private func tint(for kind: HomeActionKind) -> Color {
        switch kind {
        case .issue: return CivicTheme.amber
        case .service: return CivicTheme.green
        case .assistant: return CivicTheme.violet
        case .refresh: return CivicTheme.cyan
        case .feed: return CivicTheme.cyan
        }
    }

    private func nextVoteCard(issue: CivicIssue) -> some View {
        NavigationLink(value: issue.id) {
            CivicGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Next vote", systemImage: "calendar.badge.clock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.amber)
                        .textCase(.uppercase)
                    Text(issue.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(issue.summary)
                        .font(.system(size: 14))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(3)
                    HStack(spacing: 8) {
                        RectBadge(text: issue.scope.shortLabel, systemImage: "scope", tint: CivicTheme.violet)
                        RectBadge(text: issue.impactLevel.rawValue, systemImage: issue.impactLevel.symbolName, tint: CivicTheme.impactColor(for: issue.impactLevel))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func topFederalCard(issue: CivicIssue) -> some View {
        NavigationLink(value: issue.id) {
            CivicGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Federal pick", systemImage: "building.columns")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.cyan)
                        .textCase(.uppercase)
                    Text(issue.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(issue.jurisdiction)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var crewTile: some View {
        NavigationLink(value: HomeRoute.groups) {
            CivicGlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                            .fill(CivicTheme.violet.opacity(0.15))
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(CivicTheme.violet)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(crewTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        Text(crewSubtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CivicTheme.quietInk)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var crewTitle: String {
        store.groups.isEmpty ? "Start a crew" : "Your crew"
    }

    private var crewSubtitle: String {
        if store.groups.isEmpty {
            return "Rally neighbors and friends to file alongside you"
        }
        let memberCount = store.groups.reduce(0) { $0 + $1.members.count }
        let rallies = store.groups.reduce(0) { $0 + $1.totalRallies }
        return "\(memberCount) member\(memberCount == 1 ? "" : "s") · \(rallies) rall\(rallies == 1 ? "y" : "ies") sent"
    }

    private var cta: some View {
        NavigationLink(value: HomeRoute.issues) {
            HStack {
                Text("See all items")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.right")
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: CivicTheme.cornerRadius)
                    .stroke(CivicTheme.hairline, lineWidth: 1)
            )
            .foregroundStyle(CivicTheme.ink)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView(selectTab: { _ in })
        .environment(CivicOSStore())
}

private enum HomeActionKind: String {
    case issue
    case service
    case assistant
    case refresh
    case feed
}

private struct HomeActionItem: Identifiable {
    let id: String
    let kind: HomeActionKind
    let title: String
    let detail: String
    let cta: String
    let systemImage: String
    let tint: Color
    let issueID: CivicIssue.ID?
}
