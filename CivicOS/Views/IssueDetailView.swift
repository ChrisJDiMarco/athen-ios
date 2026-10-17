import SwiftUI

struct IssueDetailView: View {
    @Environment(CivicOSStore.self) private var store
    let issue: CivicIssue
    @State private var presentedURL: SafariURL?
    @State private var showingRallySheet = false
    @State private var presentedBrief: CivicBriefDigestItem?
    @State private var showImpactSheet: Bool = false
    @State private var briefError: String?
    @State private var showPetitionComposer: Bool = false
    @State private var presentedPetition: PetitionRef?
    @State private var showAllDetails: Bool = false

    private struct PetitionRef: Identifiable, Hashable { let id: String }

    var body: some View {
        ZStack {
            CivicTheme.screenBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    IssueHeroCard(issue: issue)
                    aiBriefCTA
                    personalImpactCTA
                    powerMapCard
                    BillTimelineCard(issueId: issue.id.uuidString)
                    petitionsRail
                    IssueWhyItMattersCard(
                        issue: issue,
                        profile: store.profile,
                        alreadySent: store.status(for: issue).isSent
                    )
                    CivicActionPlanCard(issue: issue) {
                        Haptics.selection()
                        showingRallySheet = true
                    }
                    TranslationCardView(issue: issue)
                    if BetaFeatures.outreachGroups || !store.groups.isEmpty {
                        RallyCrewCard(
                            issue: issue,
                            groupCount: store.groups.count,
                            memberCount: store.groups.reduce(0) { $0 + $1.members.count },
                            rallyCount: store.rallyCount(for: issue)
                        ) {
                            Haptics.selection()
                            showingRallySheet = true
                        }
                    }

                    // Always-visible: sent receipt + official reply (high signal)
                    if let receipt = store.status(for: issue).receipt {
                        SentReceiptCard(issue: issue, receipt: receipt)
                    }
                    if let reply = issue.reply {
                        OfficialReplyCard(reply: reply)
                    }
                    if let outcomes = voteOutcomes, !outcomes.isEmpty {
                        voteOutcomeCard(outcomes: outcomes)
                    }

                    // Secondary cards collapse behind a disclosure — most users
                    // never scroll past the brief + action plan.
                    if showAllDetails {
                        BackgroundReadingCard(
                            reading: store.backgroundByIssue[issue.id],
                            isLoading: store.loadingBackgroundFor.contains(issue.id),
                            onTapCitation: { url in presentedURL = SafariURL(url: url) }
                        )
                        RoutingCard(issue: issue)
                        IssueTimelineCard(
                            issue: issue,
                            status: store.status(for: issue),
                            rallyCount: store.rallyCount(for: issue)
                        )
                        CivicTrustCard(issue: issue) { url in
                            presentedURL = SafariURL(url: url)
                        }
                        SourceCard(issue: issue) { url in
                            presentedURL = SafariURL(url: url)
                        }
                    }
                    showDetailsButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 124)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.selection()
                    store.toggleBookmark(issue)
                } label: {
                    Image(systemName: store.isBookmarked(issue) ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(store.isBookmarked(issue) ? CivicTheme.violet : CivicTheme.mutedInk)
                }
                .accessibilityLabel(store.isBookmarked(issue) ? "Remove bookmark" : "Save for later")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                // Regulatory items (federal agency rules) don't go through
                // the email-filing pipeline; suppress the banner so we don't
                // mislead users about what "Endorse" would do.
                if !JurisdictionScope.isRegulatory(jurisdiction: issue.jurisdiction, scope: issue.scope) {
                    FilingDeliveryBanner(isGmailConnected: store.isGmailFilingEnabled && store.isGmailConnected) {
                        Haptics.selection()
                        store.queueAssistantPrompt("Walk me through connecting Gmail so Athen can send my filings from my own inbox.")
                    }
                }
                ActionBarView(issue: issue)
            }
        }
        .task {
            store.loadBackgroundIfNeeded(for: issue)
            // Make sure the "Sends from your Gmail" banner reflects current
            // truth — Composio status may be stale or empty if the user
            // hasn't opened Connected apps yet this session.
            if store.integrationStatusByApp.isEmpty {
                await store.loadIntegrations()
            }
        }
        .sheet(item: $presentedURL) { wrapper in
            SafariSheet(url: wrapper.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showingRallySheet) {
            RallyCrewSheet(issue: issue)
                .environment(store)
        }
        .sheet(item: $presentedBrief) { item in
            BriefDetailView(item: item)
                .environment(store)
        }
        .sheet(isPresented: $showPetitionComposer) {
            PetitionComposerView(prefilledIssueID: issue.id)
                .environment(store)
        }
        .sheet(item: $presentedPetition) { ref in
            PetitionDetailView(petitionID: ref.id)
                .environment(store)
        }
        .sheet(isPresented: $showImpactSheet) {
            PersonalImpactSheet(issueId: issue.id.uuidString)
                .environment(store)
        }
    }

    private var powerMapCard: some View {
        let map = issue.powerMap
        return CivicGlassCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    SectionHeader(title: "Power map", systemImage: "building.columns.fill")
                    Spacer()
                    RectBadge(text: issue.trustLabel, systemImage: "checkmark.shield.fill", tint: issue.trustScore >= 80 ? CivicTheme.green : CivicTheme.amber)
                }

                Text("Who decides, where pressure goes")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)

                VStack(spacing: 8) {
                    powerMapRow("Decision maker", map.decisionMaker, "person.crop.rectangle.fill", CivicTheme.violet)
                    powerMapRow("Venue", map.venue, "mappin.and.ellipse", CivicTheme.cyan)
                    powerMapRow("Public channel", map.publicChannel, "megaphone.fill", CivicTheme.amber)
                    powerMapRow("Source signal", map.sourceSignal, "doc.text.magnifyingglass", CivicTheme.green)
                }

                Text(map.pressurePoint)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 12))

                Button {
                    Haptics.selection()
                    store.queueAssistantPrompt("""
                    Analyze the power map for this civic issue.
                    Issue: \(issue.title)
                    Summary: \(issue.summary)
                    Decision maker: \(map.decisionMaker)
                    Venue: \(map.venue)
                    Public channel: \(map.publicChannel)
                    Source: \(map.sourceSignal)

                    Tell me who benefits, who may be affected, what claims need verification, and the most strategic thing a normal constituent can do.
                    """)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                        Text("Ask Athen who benefits")
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

    private func powerMapRow(_ title: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Personal impact CTA

    private var personalImpactCTA: some View {
        Button {
            Haptics.selection()
            showImpactSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.violet)
                VStack(alignment: .leading, spacing: 2) {
                    Text("How does this affect me?")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Text("Get a personal estimate using your own numbers")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            .padding(13)
            .background(CivicTheme.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.violet.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - AI brief CTA

    @ViewBuilder
    private var aiBriefCTA: some View {
        let id = issue.id.uuidString
        let brief = store.brief(for: id)
        let isWorking = store.generatingBriefFor.contains(id)

        VStack(spacing: 8) {
            Button {
                Haptics.selection()
                briefError = nil
                if brief != nil {
                    presentedBrief = digestItem(for: brief)
                } else {
                    Task { await generateAndPresentBrief(id: id) }
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(CivicTheme.violet.opacity(0.15))
                        if isWorking {
                            ProgressView().tint(CivicTheme.violet)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(CivicTheme.violet)
                        }
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(brief != nil ? "View AI Brief" : (isWorking ? "Athen is thinking…" : "Generate AI Brief"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        Text(brief?.headline ?? subtitleCopy)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: brief != nil ? "chevron.right" : "arrow.right.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                }
                .padding(14)
                .background(CivicTheme.violet.opacity(0.07), in: RoundedRectangle(cornerRadius: CivicTheme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: CivicTheme.cornerRadius)
                        .stroke(CivicTheme.violet.opacity(0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isWorking)

            if let briefError {
                briefErrorCard(briefError, id: id)
            }
        }
    }

    /// Pulls vote outcomes from the rep scorecard that match this issue.
    /// When the vote has happened, we surface "Senator X voted YES" with
    /// alignment to the user's filed stance.
    private var voteOutcomes: [(name: String, vote: String, aligned: Bool?)]? {
        guard let scorecards = store.repScorecard?.scorecards else { return nil }
        var out: [(String, String, Bool?)] = []
        for card in scorecards {
            for entry in card.history where entry.issueId == issue.id.uuidString {
                guard let vote = entry.vote else { continue }
                let aligned: Bool? = {
                    switch (entry.position, vote) {
                    case ("endorse", "yes"), ("oppose", "no"): return true
                    case ("endorse", "no"), ("oppose", "yes"): return false
                    default: return nil
                    }
                }()
                out.append((card.officialName, vote, aligned))
            }
        }
        return out.isEmpty ? nil : out
    }

    private func voteOutcomeCard(outcomes: [(name: String, vote: String, aligned: Bool?)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.green)
                Text("VOTE OUTCOME")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(CivicTheme.green)
                Spacer()
            }
            VStack(spacing: 8) {
                ForEach(outcomes.indices, id: \.self) { idx in
                    let entry = outcomes[idx]
                    HStack(spacing: 10) {
                        Text(entry.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CivicTheme.ink)
                        Spacer()
                        Text(entry.vote.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(voteColor(entry.vote), in: Capsule())
                        if let aligned = entry.aligned {
                            Text(aligned ? "ALIGNED" : "MISMATCH")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.4)
                                .foregroundStyle(aligned ? CivicTheme.green : CivicTheme.amber)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(CivicTheme.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.green.opacity(0.20), lineWidth: 1))
    }

    private func voteColor(_ vote: String) -> Color {
        switch vote.lowercased() {
        case "yes", "yea", "aye": return CivicTheme.green
        case "no", "nay": return CivicTheme.red
        default: return CivicTheme.mutedInk
        }
    }

    private var showDetailsButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                showAllDetails.toggle()
            }
            Haptics.selection()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showAllDetails ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                Text(showAllDetails ? "Hide background, routing, sources" : "Show background, routing, sources")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(CivicTheme.cyan)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(CivicTheme.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.cyan.opacity(0.20), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var subtitleCopy: String {
        switch store.backendStatus {
        case .online: return "Claude reads the source and writes a plain-English explainer."
        case .checking: return "Connecting…"
        case .offline, .mockMode, .unknown:
            return "Athen is offline right now. Try again in a moment."
        }
    }

    @ViewBuilder
    private var petitionsRail: some View {
        let related = store.petitions(for: issue.id)
        if related.isEmpty {
            startPetitionCallout
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                    Text("COLLECTIVE DEMANDS ON THIS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(CivicTheme.violet)
                    Spacer()
                    Button {
                        Haptics.selection()
                        showPetitionComposer = true
                    } label: {
                        Label("Start one", systemImage: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CivicTheme.violet)
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 8) {
                    ForEach(related.prefix(3)) { petition in
                        Button {
                            Haptics.selection()
                            presentedPetition = PetitionRef(id: petition.id)
                        } label: {
                            petitionRow(petition)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CivicTheme.violet.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.violet.opacity(0.18), lineWidth: 1))
        }
    }

    private var startPetitionCallout: some View {
        Button {
            Haptics.selection()
            showPetitionComposer = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(CivicTheme.violet.opacity(0.15))
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start a petition on this")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Text("Rally neighbors → one packet delivered to the right official when the threshold or deadline hits.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.violet)
            }
            .padding(12)
            .background(CivicTheme.violet.opacity(0.05), in: RoundedRectangle(cornerRadius: CivicTheme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: CivicTheme.cornerRadius).stroke(CivicTheme.violet.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 3])))
        }
        .buttonStyle(.plain)
    }

    private func petitionRow(_ petition: CivicPetition) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(petition.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: "signature")
                        .font(.system(size: 9, weight: .bold))
                    Text("\(petition.signerCount) signed")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(CivicTheme.violet)
            }
            Spacer()
            if store.signedPetitionIDs.contains(petition.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(CivicTheme.green)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
        }
        .padding(10)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private func generateAndPresentBrief(id: String) async {
        await store.generateBrief(for: id)
        if let fresh = store.brief(for: id) {
            presentedBrief = digestItem(for: fresh)
        } else if let err = store.lastBriefError {
            briefError = err
            Haptics.error()
        } else {
            briefError = "Brief generation returned nothing. Check the backend status and try again."
            Haptics.error()
        }
    }

    private func briefErrorCard(_ message: String, id: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CivicTheme.amber)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text("Brief generation failed")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Haptics.selection()
                    briefError = nil
                    Task { await generateAndPresentBrief(id: id) }
                } label: {
                    Text("Try again")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(CivicTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CivicTheme.amber.opacity(0.22), lineWidth: 1))
    }

    private func digestItem(for brief: CivicBriefAnalysis?) -> CivicBriefDigestItem {
        let ref = BriefIssueRef(
            id: issue.id.uuidString,
            title: issue.title,
            category: issue.category,
            jurisdiction: issue.jurisdiction,
            scope: scopeKey,
            stateCode: derivedStateCode,
            summary: issue.summary,
            impactLevel: issue.impactLevel.rawValue,
            voteDateISO: ISO8601DateFormatter().string(from: issue.voteDate),
            sourceName: issue.sourceName,
            sourceHost: issue.sourceHost,
            sourceURL: issue.sourceURL,
            trustScore: issue.trustScore
        )
        return CivicBriefDigestItem(issueId: issue.id.uuidString, issue: ref, brief: brief)
    }

    private var scopeKey: String {
        switch issue.scope {
        case .federal: return "federal"
        case .state: return "state"
        case .localPhilly: return "local-philly"
        }
    }

    private var derivedStateCode: String? {
        switch issue.scope {
        case let .state(code): return code
        case .localPhilly: return "PA"
        case .federal: return nil
        }
    }
}

private struct BackgroundReadingCard: View {
    let reading: BackgroundReading?
    let isLoading: Bool
    let onTapCitation: (URL) -> Void

    var body: some View {
        if let reading, reading.hasContent {
            CivicGlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Background reading", systemImage: "newspaper.fill")
                    Text(reading.summary)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .foregroundStyle(CivicTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 8) {
                        ForEach(reading.citations) { citation in
                            CitationRow(citation: citation, onTap: onTapCitation)
                        }
                    }
                }
            }
        } else if isLoading {
            CivicGlassCard {
                HStack(spacing: 10) {
                    ProgressView().tint(CivicTheme.cyan)
                    Text("Pulling reporters' coverage…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                }
            }
        } else {
            EmptyView()
        }
    }
}

private struct CitationRow: View {
    let citation: BackgroundCitation
    let onTap: (URL) -> Void

    var body: some View {
        Button {
            if let url = URL(string: citation.url) {
                Haptics.selection()
                onTap(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.violet)
                    .frame(width: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(citation.source)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(citation.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CivicTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !citation.snippet.isEmpty {
                        Text(citation.snippet)
                            .font(.system(size: 12))
                            .foregroundStyle(CivicTheme.mutedInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            .padding(12)
            .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
            .overlay(
                RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                    .stroke(CivicTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct IssueHeroCard: View {
    let issue: CivicIssue

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    RectBadge(
                        text: issue.impactLevel.rawValue,
                        systemImage: issue.impactLevel.symbolName,
                        tint: CivicTheme.impactColor(for: issue.impactLevel)
                    )

                    Spacer()

                    Text(issue.category)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text(issue.title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(issue.summary)
                        .font(.system(size: 16))
                        .lineSpacing(4)
                        .foregroundStyle(CivicTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Image(systemName: "building.columns.fill")
                        .foregroundStyle(CivicTheme.cyan)

                    Text(issue.jurisdiction)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CivicTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer()
                }
            }
        }
    }
}

private struct RoutingCard: View {
    let issue: CivicIssue

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Auto-Filing Route",
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                )

                VStack(alignment: .leading, spacing: 12) {
                    RouteStep(number: "01", text: issue.filingRoute.verificationStep)
                    RouteStep(number: "02", text: issue.filingRoute.routingStep)
                    RouteStep(number: "03", text: issue.filingRoute.destinationStep)
                }

                HStack(spacing: 10) {
                    Image(systemName: "person.text.rectangle.fill")
                        .foregroundStyle(CivicTheme.cyan)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(issue.official.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)

                        Text("\(issue.official.title) · \(issue.official.contactTarget)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .background(CivicTheme.panelElevated)
                .clipShape(RoundedRectangle(cornerRadius: CivicTheme.mediumRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CivicTheme.mediumRadius, style: .continuous)
                        .stroke(CivicTheme.hairline, lineWidth: 1)
                )
            }
        }
    }
}

private struct RouteStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.cyan)
                .frame(width: 30, height: 24)
                .background(CivicTheme.cyan.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: CivicTheme.smallRadius, style: .continuous))

            Text(text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SentReceiptCard: View {
    @Environment(CivicOSStore.self) private var store
    let issue: CivicIssue
    let receipt: FilingReceipt
    @State private var showShareSheet = false

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "Sent", systemImage: "paperplane.fill")
                    Spacer()
                    Text(receipt.confirmationCode)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(CivicTheme.green.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text("Filed as \(receipt.action.rawValue.lowercased()) to \(receipt.officialName).")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)

                Text(receipt.messagePreview)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        showShareSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .bold))
                            Text("Share filing")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(CivicTheme.cyan, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                        .shadow(color: CivicTheme.cyan.opacity(0.25), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareReceiptView(
                issue: issue,
                receipt: receipt,
                constituentLabel: constituentLabel
            )
        }
    }

    private var constituentLabel: String {
        if let profile = store.profile {
            if let locality = profile.localityLabel, !locality.isEmpty {
                return "a verified constituent in \(locality), \(profile.stateCode)"
            }
            return "a verified constituent in \(profile.stateName)"
        }
        return "a verified constituent"
    }
}

private struct OfficialReplyCard: View {
    let reply: OfficialReply

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Official Reply", systemImage: "text.bubble.fill")
                    Spacer()
                    RectBadge(text: reply.stance, systemImage: "tray.full.fill", tint: CivicTheme.violet)
                }

                Text(reply.summary)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SourceCard: View {
    let issue: CivicIssue
    let onOpenURL: (URL) -> Void

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Evidence vault", systemImage: "checkmark.shield.fill")
                    Spacer()
                    RectBadge(text: "\(issue.trustScore)%", systemImage: "gauge.with.dots.needle.bottom.50percent", tint: issue.trustScore >= 80 ? CivicTheme.green : CivicTheme.amber)
                }

                Text(issue.sourceName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)

                Text(issue.sourceDetail)
                    .font(.system(size: 13))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(issue.sourceEvidenceText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
                    .fixedSize(horizontal: false, vertical: true)

                if !issue.citations.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(issue.citations) { citation in
                            Button {
                                if let raw = citation.url,
                                   let url = URL(string: raw) {
                                    Haptics.selection()
                                    onOpenURL(url)
                                } else if let url = issue.sourceURLValue {
                                    Haptics.selection()
                                    onOpenURL(url)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "quote.opening")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(CivicTheme.violet)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(citation.label)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(CivicTheme.violet)
                                            .textCase(.uppercase)
                                        Text(citation.quote)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(3)
                                            .foregroundStyle(CivicTheme.mutedInk)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(CivicTheme.quietInk)
                                }
                                .padding(11)
                                .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let url = issue.sourceURLValue {
                    Button {
                        Haptics.selection()
                        onOpenURL(url)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "safari.fill")
                            Text("Open official source")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CivicTheme.cyan)
                        .padding(12)
                        .background(CivicTheme.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        IssueDetailView(issue: MockCivicData.issues[0])
            .environment(CivicOSStore())
            .preferredColorScheme(.light)
    }
}
