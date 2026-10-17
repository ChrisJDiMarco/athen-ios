import SwiftUI

struct ProfileView: View {
    @Environment(CivicOSStore.self) private var store
    @State private var zipDraft: String = ""
    @State private var showEditor: Bool = false
    @State private var showTopicsPicker: Bool = false
    @State private var showContextPicker: Bool = false
    @State private var showAbout: Bool = false
    @State private var showBackendSheet: Bool = false
    @State private var showSourcesSheet: Bool = false
    @State private var showBallotScanner: Bool = false
    @State private var showConnections: Bool = false
    @State private var showSavedSearches: Bool = false
    @State private var showBlockedAccounts: Bool = false
    @State private var showPetitions: Bool = false
    @State private var showVoterHub: Bool = false
    @State private var showLifeEvent: Bool = false
    @State private var showDirectory: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showDeleteFinalConfirm: Bool = false
    @State private var isDeletingData: Bool = false
    @FocusState private var zipFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        if store.profile == nil {
                            zipEntryCard
                        } else {
                            verifiedCard
                            streakCard
                            HomePulseStrip(
                                onOpenStreak: {},
                                onOpenChanges: {},
                                onOpenNextDeadline: {},
                            )
                            interestsSection
                            civicContextSection
                            crewSection
                            if store.profile?.officials.hasAny == true {
                                officialsSection
                            } else {
                                emptyOfficialsCard
                            }
                            AIQuotaCard()
                            settingsSection
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .groups:
                    GroupsListView()
                case .history:
                    FilingHistoryView()
                case .saved:
                    BookmarksView()
                }
            }
            .sheet(isPresented: $showEditor) {
                ZipEditorSheet(zipDraft: $zipDraft) { newZip in
                    Task { await store.updateZip(newZip) }
                    showEditor = false
                }
            }
            .sheet(isPresented: $showTopicsPicker) {
                TopicsPickerSheet(initial: store.profile?.interests ?? [])
                    .environment(store)
            }
            .sheet(isPresented: $showContextPicker) {
                ContextPickerSheet(initial: store.profile?.factors ?? [])
                    .environment(store)
            }
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
            .sheet(isPresented: $showBackendSheet) {
                BackendURLEditorSheet()
                    .environment(store)
            }
            .sheet(isPresented: $showSourcesSheet) {
                SourcesPanelView()
                    .environment(store)
            }
            .sheet(isPresented: $showBallotScanner) {
                BallotScannerView()
                    .environment(store)
            }
            .sheet(isPresented: $showConnections) {
                ConnectionsPanelView()
                    .environment(store)
            }
            .sheet(isPresented: $showSavedSearches) {
                SavedSearchesView()
                    .environment(store)
            }
            .sheet(isPresented: $showBlockedAccounts) {
                NavigationStack {
                    BlockedAccountsView()
                        .environment(store)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") { showBlockedAccounts = false }
                                    .foregroundStyle(CivicTheme.cyan)
                            }
                        }
                }
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
            .task { await store.checkBackendHealth() }
        }
    }

    enum ProfileRoute: Hashable { case groups, history, saved }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Profile")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .textCase(.uppercase)
            Text("You")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
        }
    }

    private var zipEntryCard: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Where do you live?", systemImage: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.cyan)
                Text("Enter your ZIP code. We use it to find your federal, state, and local representatives — nothing else.")
                    .font(.system(size: 15))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
                ZipInlineField(text: $zipDraft, isResolving: store.isResolvingProfile) {
                    Task { await store.updateZip(zipDraft) }
                }
                .focused($zipFieldFocused)
                if let err = store.profileError {
                    Text(err)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CivicTheme.red)
                }
            }
        }
        .onAppear { zipFieldFocused = true }
    }

    private var verifiedCard: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Verified", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.green)
                        .textCase(.uppercase)
                    Spacer()
                    Button {
                        zipDraft = store.profile?.zipCode ?? ""
                        showEditor = true
                    } label: {
                        Text("Change ZIP")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CivicTheme.cyan)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.profile?.displayLocation ?? "—")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Text("ZIP \(store.profile?.zipCode ?? "")")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .monospacedDigit()
                }
            }
        }
    }

    private var streakCard: some View {
        let days = store.civicStreakDays
        let filed = store.sentCount
        let saved = store.bookmarkedIssues.count
        return CivicGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(streakTint(days: days).opacity(0.16))
                        Image(systemName: days >= 7 ? "flame.fill" : "calendar.badge.checkmark")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(streakTint(days: days))
                    }
                    .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(days)-day civic streak")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                            .monospacedDigit()
                        Text(streakSubtitle(days: days))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    streakStat("\(filed)", "Filed", CivicTheme.cyan)
                    streakStat("\(saved)", "Saved", CivicTheme.amber)
                    streakStat("\(store.diffEvents.count)", "Tracked changes", CivicTheme.violet)
                }
            }
        }
    }

    private func streakStat(_ value: String, _ label: String, _ tint: Color) -> some View {
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

    private func streakTint(days: Int) -> Color {
        switch days {
        case 0...1: CivicTheme.cyan
        case 2...6: CivicTheme.amber
        default: CivicTheme.red
        }
    }

    private func streakSubtitle(days: Int) -> String {
        switch days {
        case 0: return "Open Athen tomorrow to start tracking your streak."
        case 1: return "Day one — come back tomorrow to keep it alive."
        case 2...6: return "Nice rhythm. Civic habit forming."
        case 7...29: return "A week+. You're paying attention better than most."
        default: return "Legend tier — \(days) consecutive days."
        }
    }

    @ViewBuilder
    private var interestsSection: some View {
        let interests = store.profile?.interests ?? []
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Interests")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Button {
                        showTopicsPicker = true
                    } label: {
                        Text(interests.isEmpty ? "Pick topics" : "Edit")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CivicTheme.cyan)
                    }
                    .buttonStyle(.plain)
                }
                if interests.isEmpty {
                    Text("Tap pick topics to prioritize items in your feed. Federal items always show.")
                        .font(.system(size: 14))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineSpacing(3)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(interests).sorted(by: { $0.label < $1.label })) { topic in
                            RectBadge(text: topic.label, systemImage: topic.systemImage, tint: topic.tint)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var civicContextSection: some View {
        let factors = store.profile?.factors ?? []
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Civic context")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Button {
                        showContextPicker = true
                    } label: {
                        Text(factors.isEmpty ? "Add context" : "Edit")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CivicTheme.cyan)
                    }
                    .buttonStyle(.plain)
                }

                if factors.isEmpty {
                    Text("Add what describes your household so the radar can explain why an item matters: renter, parent, commuter, business owner, and more.")
                        .font(.system(size: 14))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineSpacing(3)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(factors).sorted(by: { $0.label < $1.label })) { factor in
                            RectBadge(text: factor.label, systemImage: factor.systemImage, tint: factor.tint)
                        }
                    }
                }
            }
        }
    }

    private var crewSection: some View {
        VStack(spacing: 10) {
            lifeEventEntryTile
            voterHubTile
            directoryEntryTile
            if BetaFeatures.ballotScanner {
                ballotScannerTile
            }
            petitionsTile
            activityTile(
                title: "History",
                subtitle: filingHistorySubtitle,
                icon: "tray.full.fill",
                tint: CivicTheme.cyan,
                route: .history
            )
            activityTile(
                title: "Saved",
                subtitle: savedSubtitle,
                icon: "bookmark.fill",
                tint: CivicTheme.violet,
                route: .saved
            )
            // Outreach Groups are gated behind a beta flag. Show the tile only
            // when the flag is on OR the user already has existing groups
            // (so legacy groups stay accessible after the flag flips off).
            if BetaFeatures.outreachGroups || !store.groups.isEmpty {
                activityTile(
                    title: "Your crew",
                    subtitle: crewSubtitle,
                    icon: "person.3.fill",
                    tint: CivicTheme.amber,
                    route: .groups
                )
            }
        }
    }

    private var directoryEntryTile: some View {
        Button {
            Haptics.selection()
            showDirectory = true
        } label: {
            CivicGlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                            .fill(CivicTheme.cyan.opacity(0.15))
                        Image(systemName: "person.text.rectangle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CivicTheme.cyan)
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Directory")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(CivicTheme.ink)
                            Text("NEW")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(CivicTheme.cyan, in: Capsule())
                        }
                        Text("Every elected official in the U.S. — searchable, with socials and contact info.")
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

    private var lifeEventEntryTile: some View {
        Button {
            Haptics.selection()
            showLifeEvent = true
        } label: {
            CivicGlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                            .fill(
                                LinearGradient(
                                    colors: [CivicTheme.violet, CivicTheme.cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: "sparkles")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Life-event plans")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(CivicTheme.ink)
                            if store.lifeEventPlans.isEmpty {
                                Text("NEW")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(CivicTheme.violet, in: Capsule())
                            } else {
                                Text("\(store.lifeEventPlans.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(CivicTheme.violet)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(CivicTheme.violet.opacity(0.14), in: Capsule())
                            }
                        }
                        Text(lifeEventEntrySubtitle)
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

    private var lifeEventEntrySubtitle: String {
        if let recent = store.lifeEventPlans.first {
            return "Last: \(recent.situation)"
        }
        return "Tell Athen what's happening and get a civic + benefits plan."
    }

    private var voterHubTile: some View {
        Button {
            Haptics.selection()
            showVoterHub = true
        } label: {
            CivicGlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                            .fill(CivicTheme.amber.opacity(0.15))
                        Image(systemName: store.isElectionDay ? "checkmark.seal.fill" : "doc.text.image.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CivicTheme.amber)
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Voter Hub")
                                .font(.system(size: 16, weight: .bold))
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
                        Text(voterHubProfileSubtitle)
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

    private var voterHubProfileSubtitle: String {
        if let next = store.nextElection, let days = next.daysUntil {
            if days <= 0 { return "Polling place + ballot + your plan" }
            if days <= 14 { return "Election in \(days) days · ballot ready" }
            return "Sample ballot, registration, polling, rep scorecard"
        }
        return "Sample ballot, registration, polling, rep scorecard"
    }

    private var petitionsTile: some View {
        Button {
            Haptics.selection()
            showPetitions = true
        } label: {
            CivicGlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                            .fill(CivicTheme.violet.opacity(0.15))
                        Image(systemName: "person.3.sequence.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CivicTheme.violet)
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Petitions")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        Text(petitionsSubtitle)
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

    private var petitionsSubtitle: String {
        let signed = store.signedPetitionIDs.count
        let created = store.createdPetitionIDs.count
        if signed == 0 && created == 0 {
            return "Sign on to demands, or start your own — collective voice delivered to officials."
        }
        var parts: [String] = []
        if signed > 0 { parts.append("\(signed) signed") }
        if created > 0 { parts.append("\(created) started") }
        return parts.joined(separator: " · ")
    }

    private var ballotScannerTile: some View {
        Button {
            Haptics.selection()
            showBallotScanner = true
        } label: {
            CivicGlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                            .fill(CivicTheme.violet.opacity(0.15))
                        Image(systemName: "doc.text.image.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CivicTheme.violet)
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Scan a ballot")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(CivicTheme.ink)
                            Text("NEW")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(CivicTheme.violet, in: Capsule())
                        }
                        Text("Photograph your sample ballot and get plain-English briefs on each item.")
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

    private func activityTile(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        route: ProfileRoute
    ) -> some View {
        NavigationLink(value: route) {
            CivicGlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                            .fill(tint.opacity(0.15))
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        Text(subtitle)
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

    private var crewSubtitle: String {
        let groups = store.groups
        if groups.isEmpty {
            return "Add neighbors and friends to rally on issues"
        }
        let memberCount = groups.reduce(0) { $0 + $1.members.count }
        return "\(groups.count) crew\(groups.count == 1 ? "" : "s") · \(memberCount) member\(memberCount == 1 ? "" : "s")"
    }

    private var filingHistorySubtitle: String {
        let count = store.filingHistory.count
        return count == 0
            ? "Nothing filed yet — items you send show up here"
            : "\(count) filing\(count == 1 ? "" : "s") sent"
    }

    private var savedSubtitle: String {
        let count = store.bookmarkedIssues.count
        return count == 0
            ? "Bookmark items you want to come back to"
            : "\(count) item\(count == 1 ? "" : "s") saved"
    }

    private var settingsSection: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Settings")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .textCase(.uppercase)
                    .tracking(0.5)

                backendRow

                Divider().overlay(CivicTheme.hairline)

                sourcesRow

                Divider().overlay(CivicTheme.hairline)

                ambientBriefingRow

                Divider().overlay(CivicTheme.hairline)

                hyperlocalRow

                Divider().overlay(CivicTheme.hairline)

                if BetaFeatures.athenProPromptVisible {
                    athenProRow
                    Divider().overlay(CivicTheme.hairline)
                }

                connectionsRow

                Divider().overlay(CivicTheme.hairline)

                savedSearchesRow

                Divider().overlay(CivicTheme.hairline)

                blockedAccountsRow

                Divider().overlay(CivicTheme.hairline)

                Button {
                    Haptics.selection()
                    showAbout = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CivicTheme.cyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("About, Privacy, Terms")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(CivicTheme.ink)
                            Text("Version info, how we handle your data, contact")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CivicTheme.mutedInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CivicTheme.quietInk)
                    }
                }
                .buttonStyle(.plain)

                Divider().overlay(CivicTheme.hairline)

                deleteDataRow
            }
        }
        .alert("Delete all your Athen data?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                showDeleteFinalConfirm = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This wipes your profile, ZIP, interests, bookmarks, filings, posts, comments, and any signatures or reports tied to this install. Apple-required: can't be undone.")
        }
        .alert("Are you absolutely sure?", isPresented: $showDeleteFinalConfirm) {
            Button("Erase everything", role: .destructive) {
                Task { await performDataDeletion() }
            }
            Button("Keep my data", role: .cancel) {}
        } message: {
            Text("After this, the app reopens to the welcome screen with no history.")
        }
    }

    private var deleteDataRow: some View {
        Button {
            Haptics.selection()
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CivicTheme.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Delete my data")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CivicTheme.red)
                    Text("Erase everything stored on this device and on Athen servers")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                }
                Spacer()
                if isDeletingData {
                    ProgressView()
                        .controlSize(.small)
                        .tint(CivicTheme.red)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CivicTheme.quietInk)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDeletingData)
        .accessibilityHint("Permanently deletes your account data.")
    }

    private func performDataDeletion() async {
        isDeletingData = true
        await store.deleteAllData()
        isDeletingData = false
        Haptics.success()
    }

    private var connectionsRow: some View {
        Button {
            Haptics.selection()
            showConnections = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CivicTheme.violet)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Connected apps")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CivicTheme.ink)
                        Text(connectionsBadgeLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(CivicTheme.violet, in: Capsule())
                    }
                    Text("Send filings from Gmail, log to Notion, post to Slack, sync to Calendar.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
        }
        .buttonStyle(.plain)
    }

    private var connectionsBadgeLabel: String {
        let connected = store.integrationStatusByApp.values.filter { $0.isConnected }.count
        return connected == 0 ? "NEW" : "\(connected) on"
    }

    private var savedSearchesRow: some View {
        Button {
            Haptics.selection()
            showSavedSearches = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "scope")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CivicTheme.violet)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Saved searches")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CivicTheme.ink)
                        if !store.savedSearches.isEmpty {
                            Text("\(store.savedSearches.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(CivicTheme.violet, in: Capsule())
                        }
                    }
                    Text("Track keywords or topics. Get pinged when new matches show up.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
        }
        .buttonStyle(.plain)
    }

    private var blockedAccountsRow: some View {
        Button {
            Haptics.selection()
            showBlockedAccounts = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CivicTheme.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Blocked accounts")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CivicTheme.ink)
                    Text(store.blockedAuthors.isEmpty ? "No one blocked" : "\(store.blockedAuthors.count) blocked from Square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
        }
        .buttonStyle(.plain)
    }

    private var ambientBriefingRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "airpods.gen3")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CivicTheme.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Ambient morning briefing")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
                Text("Auto-play when AirPods or CarPlay come online between 5am–11am.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineLimit(2)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { store.settings.ambientMorningBriefingEnabled },
                set: { store.setAmbientMorningBriefing($0) }
            ))
            .labelsHidden()
            .tint(CivicTheme.green)
        }
    }

    /// Athen Pro upgrade entry. v1 scaffolds the UX without a payment
    /// flow — tapping shows an info popover. v1.1 wires StoreKit to make
    /// it a real subscription.
    private var athenProRow: some View {
        Button {
            Haptics.selection()
            store.queueAssistantPrompt("Tell me about Athen Pro — what's included and how it works.")
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                        .fill(LinearGradient(
                            colors: [CivicTheme.violet, CivicTheme.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Athen Pro")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        Text("COMING SOON")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(CivicTheme.violet, in: Capsule())
                    }
                    Text("Real-time vote tracking, family sharing, deeper analysis. $5/mo or $40/yr.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
        }
        .buttonStyle(.plain)
    }

    private var hyperlocalRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CivicTheme.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text("Hyperlocal mode")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
                Text("Hide federal items. Show only city + state bills, votes, and elections.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { store.settings.hyperlocalMode },
                set: { store.setHyperlocalMode($0) }
            ))
            .labelsHidden()
            .tint(CivicTheme.amber)
        }
    }

    private var sourcesRow: some View {
        Button {
            Haptics.selection()
            showSourcesSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CivicTheme.violet)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Data sources")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CivicTheme.ink)
                        Text(sourcesCountLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CivicTheme.violet)
                            .textCase(.uppercase)
                            .tracking(0.4)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(CivicTheme.violet.opacity(0.14), in: Capsule())
                    }
                    Text(sourcesSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
        }
        .buttonStyle(.plain)
    }

    private var sourcesCountLabel: String {
        let total = store.allSources.count
        let off = store.settings.disabledSourceIDs.count
        if total == 0 { return "Not loaded" }
        return off == 0 ? "\(total) on" : "\(total - off)/\(total) on"
    }

    private var sourcesSubtitle: String {
        if store.allSources.isEmpty {
            return "Open to load the registry, toggle sources on or off, and set refresh cadence."
        }
        let cadence = store.settings.refreshInterval.shortLabel
        let off = store.settings.disabledSourceIDs.count
        let prefix = off == 0
            ? "All \(store.allSources.count) sources enabled"
            : "\(off) hidden · \(store.allSources.count - off) feeding your radar"
        return "\(prefix) · refresh \(cadence)"
    }

    private var backendRow: some View {
        Button {
            Haptics.selection()
            showBackendSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: backendIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(backendTint)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("AI backend")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CivicTheme.ink)
                        BackendChip(status: store.backendStatus)
                    }
                    Text(backendSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
        }
        .buttonStyle(.plain)
    }

    private var backendIcon: String {
        switch store.backendStatus {
        case .online: return "bolt.horizontal.circle.fill"
        case .offline: return "exclamationmark.triangle.fill"
        case .checking: return "ellipsis.circle.fill"
        case .mockMode, .unknown: return "bolt.slash.circle.fill"
        }
    }

    private var backendTint: Color {
        switch store.backendStatus {
        case .online: return CivicTheme.green
        case .offline: return CivicTheme.red
        case .checking: return CivicTheme.cyan
        case .mockMode, .unknown: return CivicTheme.amber
        }
    }

    private var backendSubtitle: String {
        switch store.backendStatus {
        case let .online(health, url):
            return "Connected to \(url) · \(health.model)"
        case let .offline(message, url):
            return "\(url) — \(message)"
        case .checking:
            return "Checking backend…"
        case .mockMode:
            return "Running on bundled mock data. Tap to connect a backend for real AI."
        case .unknown:
            if let url = store.effectiveBackendURL?.absoluteString {
                return "Tap to verify connection to \(url)."
            }
            return "Tap to connect to localhost:8787 or your deployed backend."
        }
    }

    @ViewBuilder
    private var officialsSection: some View {
        if let officials = store.profile?.officials {
            VStack(alignment: .leading, spacing: 14) {
                if !officials.federalSenators.isEmpty || officials.federalHouseRep != nil {
                    officialsGroup(
                        title: "Federal",
                        tint: CivicTheme.cyan,
                        entries: officials.federalSenators + [officials.federalHouseRep].compactMap { $0 }
                    )
                }
                if !officials.stateSenators.isEmpty || !officials.stateRepresentatives.isEmpty {
                    officialsGroup(
                        title: "State",
                        tint: CivicTheme.violet,
                        entries: officials.stateSenators + officials.stateRepresentatives
                    )
                }
                if !officials.local.isEmpty {
                    officialsGroup(title: "Local", tint: CivicTheme.amber, entries: officials.local)
                }
            }
        }
    }

    private var emptyOfficialsCard: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("No representatives mapped", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.amber)
                Text("We haven't been able to find your reps yet. This happens when the backend can't reach the federal directory or your ZIP prefix is unassigned.")
                    .font(.system(size: 14))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
            }
        }
    }

    private func officialsGroup(title: String, tint: Color, entries: [OfficialSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .textCase(.uppercase)
            VStack(spacing: 8) {
                ForEach(entries) { entry in
                    OfficialRow(entry: entry, tint: tint)
                }
            }
        }
    }
}

private struct OfficialRow: View {
    let entry: OfficialSummary
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: CivicTheme.smallRadius)
                        .fill(tint.opacity(0.18))
                    Image(systemName: "person.fill")
                        .foregroundStyle(tint)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CivicTheme.ink)
                    Text(entry.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                    if let district = entry.district {
                        Text(district)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CivicTheme.quietInk)
                    }
                }

                Spacer()
            }
            if hasQuickActions {
                quickActions
            }
        }
        .padding(14)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                .stroke(CivicTheme.hairline, lineWidth: 1)
        )
        .shadow(color: CivicTheme.cardShadow, radius: 8, x: 0, y: 3)
    }

    private var hasQuickActions: Bool {
        entry.phone != nil || entry.email != nil || entry.websiteURL != nil
    }

    @ViewBuilder
    private var quickActions: some View {
        HStack(spacing: 8) {
            if let phone = entry.phone, let url = phoneURL(phone) {
                quickActionPill(label: "Call", systemImage: "phone.fill", tint: CivicTheme.green) {
                    open(url)
                }
            }
            if let email = entry.email, let url = URL(string: "mailto:\(email)") {
                quickActionPill(label: "Email", systemImage: "envelope.fill", tint: CivicTheme.cyan) {
                    open(url)
                }
            }
            if let website = entry.websiteURL, let url = URL(string: website) {
                quickActionPill(label: "Site", systemImage: "safari.fill", tint: tint) {
                    open(url)
                }
            }
            Spacer()
        }
    }

    private func quickActionPill(label: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) \(entry.name)")
    }

    private func phoneURL(_ phone: String) -> URL? {
        let cleaned = phone.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        return URL(string: "tel://\(cleaned)")
    }

    private func open(_ url: URL) {
        UIApplication.shared.open(url)
    }
}

private struct ZipInlineField: View {
    @Binding var text: String
    let isResolving: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("ZIP code", text: $text)
                .textFieldStyle(.plain)
                .keyboardType(.numberPad)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(CivicTheme.ink)
                .onChange(of: text) { _, newValue in
                    text = String(newValue.filter(\.isNumber).prefix(5))
                }
                .submitLabel(.done)
                .onSubmit(onSubmit)

            Button(action: onSubmit) {
                if isResolving {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(CivicTheme.cyan)
                } else {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(text.count == 5 ? CivicTheme.cyan : CivicTheme.quietInk)
                }
            }
            .disabled(text.count != 5 || isResolving)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                .stroke(CivicTheme.hairline, lineWidth: 1)
        )
    }
}

private struct ZipEditorSheet: View {
    @Binding var zipDraft: String
    let onSubmit: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            CivicTheme.screenBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("Change ZIP")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text("New ZIP looks up new representatives. We don't store the previous lookup.")
                    .font(.system(size: 14))
                    .foregroundStyle(CivicTheme.mutedInk)

                ZipInlineField(text: $zipDraft, isResolving: false) {
                    onSubmit(zipDraft)
                }
                .focused($focused)

                Spacer()
            }
            .padding(20)
        }
        .onAppear { focused = true }
        .presentationDetents([.medium])
    }
}

struct ContextPickerSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<CivicProfileFactor>

    init(initial: Set<CivicProfileFactor>) {
        _selected = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tune your radar")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(CivicTheme.ink)
                            Text("Pick only what actually describes you. \(AppBrand.name) uses this on-device profile to explain why an issue may affect your household.")
                                .font(.system(size: 14))
                                .foregroundStyle(CivicTheme.mutedInk)
                                .lineSpacing(3)
                        }

                        LazyVStack(spacing: 10) {
                            ForEach(CivicProfileFactor.allCases) { factor in
                                Button {
                                    Haptics.selection()
                                    if selected.contains(factor) {
                                        selected.remove(factor)
                                    } else {
                                        selected.insert(factor)
                                    }
                                } label: {
                                    ContextFactorRow(factor: factor, selected: selected.contains(factor))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(CivicTheme.mutedInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        store.setFactors(selected)
                        Haptics.success()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CivicTheme.cyan)
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct ContextFactorRow: View {
    let factor: CivicProfileFactor
    let selected: Bool

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                    .fill(factor.tint.opacity(selected ? 0.18 : 0.10))
                Image(systemName: factor.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(factor.tint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(factor.label)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text(topicLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(selected ? factor.tint : CivicTheme.quietInk)
        }
        .padding(13)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: CivicTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CivicTheme.cornerRadius)
                .stroke(selected ? factor.tint.opacity(0.35) : CivicTheme.hairline, lineWidth: selected ? 1.5 : 1)
        )
        .shadow(color: CivicTheme.cardShadow, radius: 8, x: 0, y: 3)
    }

    private var topicLine: String {
        factor.topics
            .sorted { $0.label < $1.label }
            .map(\.label)
            .joined(separator: " / ")
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, in: width)
        let height = rows.map { row in row.height }.reduce(0, +)
            + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, in: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let size = subviews[item.index].sizeThatFits(.unspecified)
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [(index: Int, width: CGFloat)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = size.width + (rows[rows.count - 1].items.isEmpty ? 0 : spacing)
            if rows[rows.count - 1].width + needed > width {
                rows.append(Row())
            }
            let last = rows.count - 1
            rows[last].items.append((i, size.width))
            rows[last].width += needed
            rows[last].height = max(rows[last].height, size.height)
        }
        return rows
    }
}

private struct BackendChip: View {
    let status: BackendStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(status.shortLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .textCase(.uppercase)
                .tracking(0.4)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .online: return CivicTheme.green
        case .offline: return CivicTheme.red
        case .checking: return CivicTheme.cyan
        case .mockMode, .unknown: return CivicTheme.amber
        }
    }
}

struct BackendURLEditorSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Connect AI backend")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(CivicTheme.ink)
                            Text("Point the app at a running Athen backend so chat, drafting, and news corroboration use real Claude calls. The default is http://localhost:8787.")
                                .font(.system(size: 14))
                                .foregroundStyle(CivicTheme.mutedInk)
                                .lineSpacing(3)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Backend URL")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CivicTheme.mutedInk)
                                .textCase(.uppercase)
                            TextField("http://localhost:8787", text: $draft)
                                .textFieldStyle(.plain)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.system(size: 16, design: .monospaced))
                                .foregroundStyle(CivicTheme.ink)
                                .focused($focused)
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                                .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                                .overlay(
                                    RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                                        .stroke(CivicTheme.hairline, lineWidth: 1)
                                )

                            HStack(spacing: 10) {
                                Button {
                                    draft = "http://localhost:8787"
                                } label: {
                                    Text("Use localhost")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(CivicTheme.cyan)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(CivicTheme.cyan.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                Button(role: .destructive) {
                                    draft = ""
                                } label: {
                                    Text("Clear")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(CivicTheme.red)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(CivicTheme.red.opacity(0.10), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        statusCard

                        Text("Saved URL is kept on this device only. Clear it to fall back to the bundled mock services.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CivicTheme.quietInk)
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(CivicTheme.mutedInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save & test") {
                        store.setBackendURL(draft)
                        Task {
                            await store.checkBackendHealth()
                            await MainActor.run { dismiss() }
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CivicTheme.cyan)
                }
            }
            .onAppear {
                draft = store.settings.backendURL ?? store.effectiveBackendURL?.absoluteString ?? "http://localhost:8787"
                focused = true
            }
        }
        .presentationDetents([.large])
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Status")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .textCase(.uppercase)
                BackendChip(status: store.backendStatus)
            }
            statusDetail
        }
        .padding(16)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                .stroke(CivicTheme.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch store.backendStatus {
        case let .online(health, _):
            VStack(alignment: .leading, spacing: 6) {
                detailRow("Model", health.model)
                detailRow("Email", health.email + (health.dryRun ? " (dry-run)" : ""))
                detailRow("State legislators", health.stateLegislators)
                detailRow("Firecrawl", health.firecrawl)
                detailRow("Voice", health.voice)
                detailRow("Issues loaded", "\(health.sources) sources registered")
            }
        case let .offline(message, _):
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(CivicTheme.red)
                .fixedSize(horizontal: false, vertical: true)
        case .checking:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text("Pinging /healthz…")
                    .font(.system(size: 13))
                    .foregroundStyle(CivicTheme.mutedInk)
            }
        case .mockMode:
            Text("No backend configured. Chat, drafts, and reps lookup are using bundled mock data.")
                .font(.system(size: 13))
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        case .unknown:
            Text("Tap Save & test to verify the URL.")
                .font(.system(size: 13))
                .foregroundStyle(CivicTheme.mutedInk)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CivicTheme.mutedInk)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(CivicTheme.ink)
        }
    }
}

#Preview {
    ProfileView()
        .environment(CivicOSStore())
}
