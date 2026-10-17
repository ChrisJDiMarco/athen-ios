import PhotosUI
import SwiftUI
import UIKit

// MARK: - Feed root

struct SocialFeedView: View {
    @Environment(CivicOSStore.self) private var store
    @State private var showingComposer = false
    @State private var composerSeedText: String = ""

    private let emptyStarterPrompts: [String] = [
        "Heads-up: I filed against the noise ordinance — anyone else?",
        "What does the zoning change actually mean for our block?",
        "Looking for someone who's been to a community board meeting.",
    ]
    @State private var composerIssueID: CivicIssue.ID?
    @State private var editingPost: SocialPost?
    @State private var presentedThreadID: SocialPost.ID?
    @State private var pendingPostDelete: SocialPost?
    @State private var reportingPost: SocialPost?
    @State private var pendingBlockHandle: String?
    @State private var activeFilter: FeedFilter = .all
    @State private var activeTopic: CivicTopic? = nil
    /// Scope chip — defaults to neighborhood when hyperlocal is ON, city
    /// otherwise. Persists for the lifetime of the view; the user can override
    /// without flipping the global hyperlocal setting.
    @State private var scope: SquareScope = .city
    @State private var scopeDidSync: Bool = false
    @State private var showingStats: Bool = false
    @State private var activeSort: FeedSort = .new
    @State private var showingSaved: Bool = false
    @State private var savedOnly: Bool = false
    @State private var activeHashtag: String? = nil
    @State private var presentedAuthor: String? = nil
    @State private var presentedRepostOriginal: SocialPost.ID? = nil
    @State private var showingFilterSheet: Bool = false

    /// "Where am I posting / reading?" toggle for the Square.
    /// Neighborhood = your blocks only · City = your whole city · Nation = everyone.
    enum SquareScope: String, CaseIterable, Identifiable {
        case neighborhood, city, nation

        var id: String { rawValue }

        var label: String {
            switch self {
            case .neighborhood: "Block"
            case .city: "City"
            case .nation: "Nation"
            }
        }

        var longLabel: String {
            switch self {
            case .neighborhood: "Your blocks"
            case .city: "City-wide"
            case .nation: "Everywhere"
            }
        }

        var icon: String {
            switch self {
            case .neighborhood: "house.lodge.fill"
            case .city: "building.2.fill"
            case .nation: "globe.americas.fill"
            }
        }

        var tint: Color {
            switch self {
            case .neighborhood: CivicTheme.green
            case .city: CivicTheme.cyan
            case .nation: CivicTheme.violet
            }
        }
    }

    enum FeedFilter: String, CaseIterable, Identifiable {
        case all, discuss, briefs, actions, events, questions
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: "All"
            case .discuss: "Discuss"
            case .briefs: "Briefs"
            case .actions: "Actions"
            case .events: "Events"
            case .questions: "Questions"
            }
        }

        func includes(_ kind: SocialPostKind) -> Bool {
            switch self {
            case .all: return true
            case .discuss: return kind == .discussion
            case .briefs: return kind == .aiBrief || kind == .explainer
            case .actions: return kind == .filed || kind == .rally
            case .events: return kind == .event
            case .questions: return kind == .question
            }
        }
    }

    enum FeedSort: String, CaseIterable, Identifiable {
        case new, hot, top
        var id: String { rawValue }

        var label: String {
            switch self {
            case .new: "New"
            case .hot: "Hot"
            case .top: "Top"
            }
        }

        var icon: String {
            switch self {
            case .new: "clock.fill"
            case .hot: "flame.fill"
            case .top: "arrow.up.right.circle.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14, pinnedViews: [.sectionHeaders]) {
                        squareHeaderSection
                        squareControlsSection
                        Section {
                            squareFeedSection
                            Color.clear.frame(height: 36)
                        } header: {
                            stickyScopeBar
                        }
                    }
                }
                .refreshable {
                    await store.refreshSquare()
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                if !scopeDidSync {
                    scope = store.settings.hyperlocalMode ? .neighborhood : .city
                    scopeDidSync = true
                }
            }
            .onChange(of: store.settings.hyperlocalMode) { _, newValue in
                // Keep scope in sync with the global hyperlocal toggle so the
                // setting actually steers what the user sees on Square.
                scope = newValue ? .neighborhood : .city
            }
            .navigationDestination(for: CivicIssue.ID.self) { id in
                if let issue = store.issue(with: id) {
                    IssueDetailView(issue: issue)
                }
            }
            .sheet(isPresented: $showingComposer, onDismiss: { composerSeedText = "" }) {
                CreateSocialPostSheet(
                    initialIssueID: composerIssueID,
                    editingPost: nil,
                    initialBody: composerSeedText,
                )
                .environment(store)
            }
            .sheet(isPresented: $showingStats) {
                SquareStatsSheet(
                    scope: scope,
                    scopeContextText: scopeContextText,
                    visibleCount: filteredPosts.count,
                    totalPosts: store.socialPosts.count,
                    actionCount: store.socialActionCount,
                    totalReach: totalReach,
                )
            }
            .sheet(item: Binding(
                get: { presentedAuthor.map { AuthorHandle(id: $0) } },
                set: { presentedAuthor = $0?.id }
            )) { handle in
                AuthorProfileSheet(handle: handle.id)
                    .environment(store)
            }
            .sheet(item: Binding(
                get: { presentedRepostOriginal.map { RepostOriginalHandle(id: $0) } },
                set: { presentedRepostOriginal = $0?.id }
            )) { handle in
                RepostComposerSheet(originalID: handle.id)
                    .environment(store)
            }
            .sheet(isPresented: $showingFilterSheet) {
                SquareFilterSheet(
                    activeFilter: $activeFilter,
                    activeTopic: $activeTopic,
                    activeHashtag: $activeHashtag,
                    activeSort: $activeSort,
                    savedOnly: $savedOnly,
                )
            }
            .sheet(item: $editingPost) { post in
                CreateSocialPostSheet(initialIssueID: post.issueID, editingPost: post)
                    .environment(store)
            }
            .sheet(item: Binding(
                get: { presentedThreadID.map { ThreadHandle(id: $0) } },
                set: { presentedThreadID = $0?.id }
            )) { handle in
                PostThreadView(postID: handle.id)
                    .environment(store)
            }
            .confirmationDialog(
                "Delete this post?",
                isPresented: Binding(
                    get: { pendingPostDelete != nil },
                    set: { if !$0 { pendingPostDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let post = pendingPostDelete {
                        store.deletePost(post.id)
                        Haptics.impact(.medium)
                    }
                    pendingPostDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingPostDelete = nil }
            }
            .sheet(item: $reportingPost) { post in
                ReportPostSheet(post: post) { reason in
                    store.reportPost(post.id, reason: reason)
                    Haptics.impact(.medium)
                    reportingPost = nil
                }
                .environment(store)
            }
            .confirmationDialog(
                "Block this account?",
                isPresented: Binding(
                    get: { pendingBlockHandle != nil },
                    set: { if !$0 { pendingBlockHandle = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingBlockHandle
            ) { handle in
                Button("Block \(handle)", role: .destructive) {
                    store.blockAuthor(handle)
                    Haptics.impact(.medium)
                    pendingBlockHandle = nil
                }
                Button("Cancel", role: .cancel) { pendingBlockHandle = nil }
            } message: { handle in
                Text("You won't see posts or comments from \(handle) again. You can unblock from Settings.")
            }
            .onAppear(perform: openQueuedComposerIfNeeded)
            .onChange(of: store.pendingSocialIssueID) { _, _ in
                openQueuedComposerIfNeeded()
            }
        }
    }

    private var filteredPosts: [SocialPost] {
        let base = store.visibleSocialPosts
            .filter { activeFilter.includes($0.kind) }
            .filter { post in
                guard let topic = activeTopic else { return true }
                guard let issueID = post.issueID,
                      let issue = store.issue(with: issueID)
                else { return false }
                return issue.topics.contains(topic)
            }
            .filter { matchesScope($0) }
            .filter { !savedOnly || store.savedPostIDs.contains($0.id) }
            .filter { post in
                guard let tag = activeHashtag else { return true }
                return SquareTokenizer.hashtags(in: post.body).contains(tag.lowercased())
            }
        let sorted = applySort(base)
        // Pin (only matters in City scope so announcements get top placement).
        guard scope == .city else { return sorted }
        let pinned = sorted.filter { $0.isPinned }
        let rest = sorted.filter { !$0.isPinned }
        return pinned + rest
    }

    /// Sort the visible feed. New = newest first (default). Hot = recent
    /// activity weighted (reactions + comments * 2, decayed by age). Top =
    /// raw reaction count over the last 7 days.
    private func applySort(_ posts: [SocialPost]) -> [SocialPost] {
        switch activeSort {
        case .new:
            return posts.sorted { $0.createdAt > $1.createdAt }
        case .hot:
            let now = Date.now
            return posts.sorted { a, b in
                hotScore(a, now: now) > hotScore(b, now: now)
            }
        case .top:
            let cutoff = Date.now.addingTimeInterval(-7 * 86400)
            return posts.sorted { a, b in
                let aScore = a.createdAt >= cutoff ? engagement(a) : 0
                let bScore = b.createdAt >= cutoff ? engagement(b) : 0
                if aScore == bScore { return a.createdAt > b.createdAt }
                return aScore > bScore
            }
        }
    }

    private func engagement(_ post: SocialPost) -> Int {
        post.reactions.total + post.commentCount * 2 + post.likeCount
    }

    private func hotScore(_ post: SocialPost, now: Date) -> Double {
        let ageHours = max(1.0, now.timeIntervalSince(post.createdAt) / 3600)
        return Double(engagement(post)) / pow(ageHours, 0.6)
    }

    /// Decide whether a post belongs in the current scope.
    ///
    /// - Neighborhood: locality string must match the user's city/locality
    ///   label exactly OR (when no profile) any post passes through.
    /// - City: locality must contain the user's city name OR the issue
    ///   attached to the post resolves to the user's state.
    /// - Nation: everything passes.
    ///
    /// Posts authored by the install always pass (your own voice always
    /// shows up to you regardless of scope) — otherwise toggling scope
    /// could hide your own filing receipt from the wrong tab.
    private func matchesScope(_ post: SocialPost) -> Bool {
        if scope == .nation { return true }
        guard let profile = store.profile else { return true }
        let mine = post.authorHandle.contains("you") || post.authorHandle == myHandle
        if mine { return true }

        let postLocality = post.locality.lowercased()
        let city = (profile.localityLabel ?? "").lowercased()
        let state = profile.stateName.lowercased()
        let stateCode = profile.stateCode.lowercased()

        switch scope {
        case .neighborhood:
            // Tight match — same city/locality label exactly. We don't have
            // block-level metadata yet, so "neighborhood" == "your city"
            // when city is known, otherwise nothing.
            guard !city.isEmpty else { return false }
            return postLocality.contains(city)
        case .city:
            // Looser — city name OR state name OR state code OR an issue tied
            // to this post is sourced from the user's state.
            if !city.isEmpty && postLocality.contains(city) { return true }
            if !state.isEmpty && postLocality.contains(state) { return true }
            if !stateCode.isEmpty && postLocality.contains(stateCode) { return true }
            if let issueID = post.issueID, let issue = store.issue(with: issueID) {
                let ji = issue.jurisdiction.lowercased()
                if !city.isEmpty && ji.contains(city) { return true }
                if !state.isEmpty && ji.contains(state) { return true }
                if !stateCode.isEmpty && ji.contains(stateCode) { return true }
            }
            return false
        case .nation:
            return true
        }
    }

    private var myHandle: String {
        // Mirror the handle the store assigns when authoring posts.
        guard let profile = store.profile, !profile.zipCode.isEmpty else { return "" }
        return "@you.\(profile.zipCode.prefix(3))"
    }

    private var topicChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                topicChip(label: "All topics", topic: nil)
                ForEach(CivicTopic.allCases) { topic in
                    topicChip(label: topic.label, topic: topic)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
    }

    private func topicChip(label: String, topic: CivicTopic?) -> some View {
        let active = activeTopic == topic
        return Button {
            Haptics.selection()
            activeTopic = topic
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(active ? .white : (topic?.tint ?? CivicTheme.mutedInk))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(active ? (topic?.tint ?? CivicTheme.ink) : (topic?.tint ?? CivicTheme.mutedInk).opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Open petitions surface — never empty so the social feed has something
    /// actionable to engage with even with no posts. Backend already returns
    /// region-relevant petitions via the user's ZIP query param.
    private var neighborhoodPetitions: [CivicPetition] {
        store.petitions
            .filter { $0.status == .open }
            .prefix(5)
            .map { $0 }
    }

    private var neighborhoodActionRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: scope == .neighborhood ? "house.lodge.fill" : "building.2.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(scope.tint)
                Text(scope == .neighborhood ? "PETITIONS ON YOUR BLOCK" : "OPEN IN YOUR CITY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(CivicTheme.mutedInk)
                Spacer()
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(neighborhoodPetitions) { petition in
                        Button {
                            Haptics.selection()
                            store.queueAssistantPrompt("Tell me about the petition: \(petition.title)")
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 5) {
                                    Image(systemName: "person.3.sequence.fill")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("\(petition.signerCount) signed")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundStyle(CivicTheme.violet)
                                Text(petition.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(CivicTheme.ink)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Text("Tap to learn more")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(CivicTheme.cyan)
                            }
                            .padding(12)
                            .frame(width: 220, height: 130, alignment: .leading)
                            .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Body sections (extracted for compiler type-check budget)

    @ViewBuilder
    private var squareHeaderSection: some View {
        header
            .padding(.horizontal, 20)
            .padding(.top, 16)
    }

    @ViewBuilder
    private var squareControlsSection: some View {
        if !store.radarInsights.isEmpty {
            aiExplainerStarterRail
        }

        TrendingHashtagStrip(
            posts: store.visibleSocialPosts,
            activeHashtag: activeHashtag,
            onTap: { newTag in activeHashtag = newTag },
        )
        .padding(.horizontal, 20)

        if scope != .nation && !neighborhoodPetitions.isEmpty {
            neighborhoodActionRail
        }
    }

    private var aiExplainerStarterRail: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.violet)
                Text("AI EXPLAINERS TO SHARE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(CivicTheme.mutedInk)
                Spacer()
                Button {
                    Haptics.selection()
                    activeFilter = .briefs
                    activeSort = .hot
                } label: {
                    Text("Briefs")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.radarInsights.prefix(6)) { insight in
                        explainerStarterCard(insight)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollClipDisabled()
        }
    }

    private func explainerStarterCard(_ insight: CivicRadarInsight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: insight.issue.id) {
                VStack(alignment: .leading, spacing: 7) {
                    RectBadge(
                        text: insight.issue.civicLoopStep(alreadySent: store.status(for: insight.issue).isSent),
                        systemImage: "text.magnifyingglass",
                        tint: CivicTheme.violet
                    )
                    Text(insight.issue.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(insight.reason)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(2)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {
                    Haptics.selection()
                    store.queueAssistantPrompt(explainerPrompt(for: insight))
                } label: {
                    Label("Explain", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(CivicTheme.violet, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.selection()
                    composerIssueID = insight.issue.id
                    composerSeedText = socialExplainerSeed(for: insight)
                    showingComposer = true
                } label: {
                    Label("Post", systemImage: "plus.bubble.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CivicTheme.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(CivicTheme.cyan.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .frame(width: 238, height: 180, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [CivicTheme.violet.opacity(0.08), CivicTheme.cyan.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.violet.opacity(0.18), lineWidth: 1))
    }

    private func explainerPrompt(for insight: CivicRadarInsight) -> String {
        """
        Turn this civic issue into a social-feed explainer anyone can understand.
        Issue: \(insight.issue.title)
        Summary: \(insight.issue.summary)
        Why it matters to me: \(insight.reason)
        Power map: \(insight.issue.powerMap.decisionMaker), \(insight.issue.powerMap.venue), \(insight.issue.powerMap.publicChannel)
        Source: \(insight.issue.sourceName), \(insight.issue.trustLabel)

        Give me:
        1. a plain-English post
        2. why supporters might favor it
        3. what critics might worry about
        4. what a normal person can do next
        """
    }

    private func socialExplainerSeed(for insight: CivicRadarInsight) -> String {
        "Plain-English breakdown request: \(insight.issue.title)\n\nWhat it is: \(insight.issue.summary)\n\nWhy it matters here: \(insight.reason)\n\nNext step: \(insight.recommendedAction)"
    }

    /// Sticky bar pinned at the top of the Square feed. Holds the scope
    /// tabs (neighborhood / city / nation), the filter+stats row, and the
    /// occasional brief-refresh status. Stays visible while the feed
    /// scrolls underneath.
    @ViewBuilder
    private var stickyScopeBar: some View {
        VStack(spacing: 8) {
            scopeSegmentedControl
                .padding(.horizontal, 20)
            scopeContextLine
                .padding(.horizontal, 20)
            if store.isRefreshingAthenBriefs {
                briefRefreshStatus
                    .padding(.horizontal, 20)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CivicTheme.screenBackground
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(CivicTheme.hairline)
                        .frame(height: 0.5)
                }
        )
    }

    @ViewBuilder
    private var squareFeedSection: some View {
        // Padding-top adds breathing room from the sticky filter strip.
        Color.clear.frame(height: 4)
        ForEach(filteredPosts) { post in
            SocialPostCard(
                post: post,
                onOpenThread: { presentedThreadID = post.id },
                onEdit: { editingPost = post },
                onDelete: { pendingPostDelete = post },
                onReport: { reportingPost = post },
                onBlock: { pendingBlockHandle = post.authorHandle },
                onTapAuthor: { _ in presentedAuthor = post.authorHandle },
                onRepost: { presentedRepostOriginal = post.id },
                onTapHashtag: { tag in activeHashtag = tag.lowercased() },
                onTapMention: { mention in presentedAuthor = mention },
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 4)  // air between cards
        }
        if filteredPosts.isEmpty && !store.isRefreshingAthenBriefs {
            emptyState
                .padding(.horizontal, 20)
                .padding(.top, 24)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(scope.tint)
                        .frame(width: 7, height: 7)
                    Text(scope == .nation ? "Open square" : "Public square")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
                Text("Square")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
            }

            Spacer()

            Button {
                Haptics.selection()
                showingComposer = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(CivicTheme.cyan, in: Circle())
                    .shadow(color: CivicTheme.cyan.opacity(0.30), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New post")
        }
    }

    private var scopeSegmentedControl: some View {
        HStack(spacing: 4) {
            ForEach(SquareScope.allCases) { option in
                let active = scope == option
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        scope = option
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.icon)
                            .font(.system(size: 12, weight: .bold))
                        Text(option.label)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(active ? .white : CivicTheme.mutedInk)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(
                        Group {
                            if active {
                                Capsule().fill(option.tint)
                            } else {
                                Color.clear
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.longLabel) scope")
            }
        }
        .padding(4)
        .background(CivicTheme.panelElevated, in: Capsule())
        .overlay(Capsule().stroke(CivicTheme.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private var scopeContextLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(scope.tint)
            Text(scopeContextText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            filterButton
            statsButton
        }
    }

    /// Hamburger that opens the unified filter sheet (post type + topic +
    /// hashtag + sort + saved-only). Replaces the inline sort dropdown,
    /// save bookmark, and the row of post-type chips.
    private var filterButton: some View {
        Button {
            Haptics.selection()
            showingFilterSheet = true
        } label: {
            Image(systemName: hasActiveFilter
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(hasActiveFilter ? .white : CivicTheme.mutedInk)
                .frame(width: 30, height: 28)
                .background(
                    Group {
                        if hasActiveFilter {
                            Capsule().fill(CivicTheme.violet)
                        } else {
                            Capsule().fill(CivicTheme.panelElevated)
                        }
                    }
                )
                .overlay(Capsule().stroke(CivicTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open filters")
    }

    private var hasActiveFilter: Bool {
        activeFilter != .all || activeTopic != nil || activeHashtag != nil
            || activeSort != .new || savedOnly
    }

    private var statsButton: some View {
        Button {
            Haptics.selection()
            showingStats = true
        } label: {
            HStack(spacing: 3) {
                Text("\(filteredPosts.count)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.8)
            }
            .foregroundStyle(CivicTheme.quietInk)
            .frame(minWidth: 30, minHeight: 28)
            .padding(.horizontal, 8)
            .background(CivicTheme.panelElevated, in: Capsule())
            .overlay(Capsule().stroke(CivicTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filteredPosts.count) posts — tap for stats")
    }

    private var scopeContextText: String {
        let where_ = store.profile?.displayLocation ?? "your area"
        switch scope {
        case .neighborhood:
            return "Your blocks in \(where_)"
        case .city:
            return "City-wide in \(store.profile?.localityLabel ?? where_)"
        case .nation:
            return "Everyone, everywhere"
        }
    }

    private var pulseRow: some View {
        HStack(spacing: 10) {
            PulseTile(value: "\(store.socialPosts.count)", label: "Posts", tint: CivicTheme.cyan, icon: "tray.full.fill")
            PulseTile(value: "\(store.socialActionCount)", label: "Actions", tint: CivicTheme.green, icon: "paperplane.fill")
            PulseTile(value: "\(totalReach)", label: "Signals", tint: CivicTheme.violet, icon: "waveform.path.ecg")
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedFilter.allCases) { filter in
                    let active = activeFilter == filter
                    Button {
                        Haptics.selection()
                        activeFilter = filter
                    } label: {
                        Text(filter.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(active ? .white : CivicTheme.mutedInk)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(active ? CivicTheme.ink : CivicTheme.panelElevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $activeSort) {
                ForEach(FeedSort.allCases) { option in
                    Label(option.label, systemImage: option.icon)
                        .tag(option)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: activeSort.icon)
                    .font(.system(size: 10, weight: .bold))
                Text(activeSort.label)
                    .font(.system(size: 11, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundStyle(CivicTheme.ink)
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(CivicTheme.panelElevated, in: Capsule())
            .overlay(Capsule().stroke(CivicTheme.hairline, lineWidth: 1))
        }
        .accessibilityLabel("Sort: \(activeSort.label)")
    }

    private var savedToggleButton: some View {
        Button {
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.18)) { savedOnly.toggle() }
        } label: {
            Image(systemName: savedOnly ? "bookmark.fill" : "bookmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(savedOnly ? .white : CivicTheme.mutedInk)
                .frame(width: 28, height: 28)
                .background(
                    Group {
                        if savedOnly {
                            Capsule().fill(CivicTheme.amber)
                        } else {
                            Capsule().fill(CivicTheme.panelElevated)
                        }
                    }
                )
                .overlay(Capsule().stroke(CivicTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(savedOnly ? "Showing saved only — tap to show all" : "Show saved posts only")
    }

    @ViewBuilder
    private var briefRefreshStatus: some View {
        if store.isRefreshingAthenBriefs {
            HStack(spacing: 10) {
                ProgressView().tint(CivicTheme.violet)
                Text("Generating fresh Athen Briefs…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(CivicTheme.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.violet.opacity(0.18), lineWidth: 1))
        } else if let error = store.lastAthenBriefRefreshError {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CivicTheme.amber)
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(CivicTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.amber.opacity(0.18), lineWidth: 1))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(CivicTheme.cyan.opacity(0.12))
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
            }
            .frame(width: 64, height: 64)

            VStack(spacing: 4) {
                Text(store.socialPosts.isEmpty ? "Your Square is fresh" : "No posts in this filter")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text(store.socialPosts.isEmpty
                     ? "Be the first voice on your block. Post a filing, ask a question, or share an explainer — neighbors see what you put here."
                     : "Try another filter — All shows everything you've posted.")
                    .font(.system(size: 13))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            if store.socialPosts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick starts")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.quietInk)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    ForEach(emptyStarterPrompts, id: \.self) { prompt in
                        Button {
                            Haptics.selection()
                            composerSeedText = prompt
                            showingComposer = true
                        } label: {
                            HStack {
                                Text(prompt)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(CivicTheme.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(CivicTheme.cyan)
                            }
                            .padding(12)
                            .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(CivicTheme.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }

            Button {
                Haptics.selection()
                showingComposer = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .bold))
                    Text("Compose a post")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(CivicTheme.cyan, in: Capsule())
                .shadow(color: CivicTheme.cyan.opacity(0.25), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private struct ThreadHandle: Identifiable {
        let id: SocialPost.ID
    }

    private struct AuthorHandle: Identifiable {
        let id: String
    }

    private struct RepostOriginalHandle: Identifiable {
        let id: SocialPost.ID
    }

    private var totalReach: Int {
        store.socialPosts.reduce(0) { $0 + $1.likeCount + $1.commentCount + $1.shareCount }
    }

    private func openQueuedComposerIfNeeded() {
        guard let issueID = store.consumePendingSocialIssueID() else { return }
        composerIssueID = issueID
        showingComposer = true
    }
}

// MARK: - Pulse tile

private struct PulseTile: View {
    let value: String
    let label: String
    let tint: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
    }
}

// MARK: - Filter sheet

/// One-stop modal for sort + saved + topic + hashtag filters. Replaces the
/// always-visible topic chip row that was eating screen real estate.
private struct SquareFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var activeFilter: SocialFeedView.FeedFilter
    @Binding var activeTopic: CivicTopic?
    @Binding var activeHashtag: String?
    @Binding var activeSort: SocialFeedView.FeedSort
    @Binding var savedOnly: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        postTypeSection
                        Divider().overlay(CivicTheme.hairline)
                        sortSection
                        Divider().overlay(CivicTheme.hairline)
                        savedSection
                        Divider().overlay(CivicTheme.hairline)
                        topicSection
                        if activeHashtag != nil {
                            Divider().overlay(CivicTheme.hairline)
                            hashtagSection
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        activeFilter = .all
                        activeTopic = nil
                        activeHashtag = nil
                        activeSort = .new
                        savedOnly = false
                    }
                    .foregroundStyle(CivicTheme.mutedInk)
                    .disabled(activeFilter == .all && activeTopic == nil && activeHashtag == nil && activeSort == .new && !savedOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var postTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("POST TYPE")
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(SocialFeedView.FeedFilter.allCases) { filter in
                    let active = activeFilter == filter
                    Button {
                        Haptics.selection()
                        activeFilter = filter
                    } label: {
                        Text(filter.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(active ? .white : CivicTheme.mutedInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(active ? CivicTheme.ink : CivicTheme.panelElevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SORT BY")
            HStack(spacing: 8) {
                ForEach(SocialFeedView.FeedSort.allCases) { option in
                    let active = activeSort == option
                    Button {
                        Haptics.selection()
                        activeSort = option
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: option.icon)
                                .font(.system(size: 11, weight: .bold))
                            Text(option.label)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(active ? .white : CivicTheme.mutedInk)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(active ? CivicTheme.ink : CivicTheme.panelElevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var savedSection: some View {
        Toggle(isOn: $savedOnly) {
            HStack(spacing: 8) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(CivicTheme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved posts only")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CivicTheme.ink)
                    Text("Show only posts you've bookmarked")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                }
            }
        }
        .tint(CivicTheme.amber)
    }

    private var topicSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TOPICS")
            FlowLayout(spacing: 6, lineSpacing: 6) {
                topicChip(label: "All", isActive: activeTopic == nil, tint: CivicTheme.mutedInk) {
                    activeTopic = nil
                }
                ForEach(CivicTopic.allCases) { topic in
                    topicChip(label: topic.label, isActive: activeTopic == topic, tint: topic.tint) {
                        activeTopic = (activeTopic == topic) ? nil : topic
                    }
                }
            }
        }
    }

    private var hashtagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("HASHTAG")
            HStack {
                Text(activeHashtag ?? "")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.violet)
                Spacer()
                Button {
                    activeHashtag = nil
                } label: {
                    Text("Clear")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(CivicTheme.violet.opacity(0.10), in: Capsule())
        }
    }

    private func topicChip(label: String, isActive: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isActive ? .white : tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isActive ? tint : tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(CivicTheme.mutedInk)
    }
}

// MARK: - Square stats sheet

/// Surfaces the three metric tiles that used to live above the feed. Moved
/// behind a tap because the values are mostly zero for new users and the
/// space is better spent on actual posts.
private struct SquareStatsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let scope: SocialFeedView.SquareScope
    let scopeContextText: String
    let visibleCount: Int
    let totalPosts: Int
    let actionCount: Int
    let totalReach: Int

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(scope.tint)
                        Text(scopeContextText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CivicTheme.mutedInk)
                    }

                    HStack(spacing: 10) {
                        PulseTile(value: "\(visibleCount)", label: "In view", tint: scope.tint, icon: "eye.fill")
                        PulseTile(value: "\(totalPosts)", label: "All posts", tint: CivicTheme.cyan, icon: "tray.full.fill")
                    }
                    HStack(spacing: 10) {
                        PulseTile(value: "\(actionCount)", label: "Actions", tint: CivicTheme.green, icon: "paperplane.fill")
                        PulseTile(value: "\(totalReach)", label: "Signals", tint: CivicTheme.violet, icon: "waveform.path.ecg")
                    }

                    explainerCard

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .navigationTitle("Square activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
                Text("How counts work")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(CivicTheme.mutedInk)
                    .textCase(.uppercase)
            }
            Text("**In view** is what the current scope + filters show. **All posts** counts everything you've ever stored. **Actions** is filings + rallies you've shared. **Signals** is reactions across all your posts.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
    }
}

// MARK: - Post card (top-level layout)

private struct SocialPostCard: View {
    @Environment(CivicOSStore.self) private var store
    let post: SocialPost
    let onOpenThread: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    var onTapAuthor: ((String) -> Void)? = nil
    var onRepost: (() -> Void)? = nil
    var onTapHashtag: ((String) -> Void)? = nil
    var onTapMention: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if post.isPinned {
                HStack {
                    PinnedBadge()
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            PostHeader(
                post: post,
                isMine: store.isMyPost(post),
                onEdit: onEdit,
                onDelete: onDelete,
                onTapAuthor: onTapAuthor,
            )
                .padding(.horizontal, 16)
                .padding(.top, post.isPinned ? 6 : 14)
                .padding(.bottom, 12)

            // Optional real photo only — never a fake placeholder.
            if let data = post.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()
            }

            content
                .padding(.horizontal, 16)
                .padding(.top, post.imageData == nil ? 0 : 14)
                .padding(.bottom, 4)

            PostActionBar(post: post, onOpenThread: onOpenThread)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(CivicTheme.panelElevated.opacity(0.5))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(CivicTheme.hairline)
                        .frame(height: 1)
                }
        }
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(CivicTheme.hairline, lineWidth: 1))
        .shadow(color: CivicTheme.cardShadow, radius: 14, x: 0, y: 6)
        .contextMenu {
            Button {
                Haptics.selection()
                onOpenThread()
            } label: {
                Label("Open thread", systemImage: "bubble.left.and.bubble.right.fill")
            }
            if store.isMyPost(post) {
                Button {
                    Haptics.selection()
                    onEdit()
                } label: {
                    Label("Edit post", systemImage: "pencil")
                }
                Button {
                    Haptics.selection()
                    _ = store.toggleSavedPost(post.id)
                } label: {
                    Label(
                        store.isSaved(post.id) ? "Remove from saved" : "Save post",
                        systemImage: store.isSaved(post.id) ? "bookmark.slash.fill" : "bookmark.fill",
                    )
                }
                Button {
                    Haptics.selection()
                    store.togglePinned(post.id)
                } label: {
                    Label(
                        post.isPinned ? "Unpin from City" : "Pin to City",
                        systemImage: post.isPinned ? "pin.slash.fill" : "pin.fill",
                    )
                }
                Button(role: .destructive) {
                    Haptics.impact(.light)
                    onDelete()
                } label: {
                    Label("Delete post", systemImage: "trash")
                }
            } else {
                Button {
                    Haptics.selection()
                    onRepost?()
                } label: {
                    Label("Repost with comment", systemImage: "arrow.2.squarepath")
                }
                Button {
                    Haptics.selection()
                    _ = store.toggleSavedPost(post.id)
                } label: {
                    Label(
                        store.isSaved(post.id) ? "Remove from saved" : "Save post",
                        systemImage: store.isSaved(post.id) ? "bookmark.slash.fill" : "bookmark.fill",
                    )
                }
                Button {
                    Haptics.selection()
                    _ = store.toggleMuteThread(post.id)
                } label: {
                    Label(
                        store.isMuted(post.id) ? "Unmute thread" : "Mute thread",
                        systemImage: store.isMuted(post.id) ? "bell.fill" : "bell.slash.fill",
                    )
                }
                Button(role: .destructive) {
                    Haptics.impact(.light)
                    onReport()
                } label: {
                    Label("Report post", systemImage: "flag.fill")
                }
                Button(role: .destructive) {
                    Haptics.impact(.light)
                    onBlock()
                } label: {
                    Label("Block \(post.authorHandle)", systemImage: "hand.raised.fill")
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let explainer = post.explainer {
                BriefBody(explainer: explainer, tint: post.kind.tint)
            } else if !post.body.isEmpty {
                RichPostBody(
                    body: post.body,
                    onHashtag: onTapHashtag,
                    onMention: onTapMention,
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            if let repostID = post.repostOfID {
                RepostPreview(originalID: repostID)
            }

            if post.kind == .event {
                EventRSVPRow(post: post)
            }

            if post.kind == .poll {
                PollCard(post: post)
            }

            if let issue = linkedIssue {
                LinkedIssueChip(issue: issue)
            }
        }
    }

    private var linkedIssue: CivicIssue? {
        guard let id = post.issueID else { return nil }
        return store.issue(with: id)
    }
}

// MARK: - Header

private struct PostHeader: View {
    let post: SocialPost
    let isMine: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    var onTapAuthor: ((String) -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                if !isMine { onTapAuthor?(post.authorHandle) }
            } label: {
                ZStack {
                    Circle().fill(post.kind.tint.opacity(0.16))
                    Text(post.authorEmoji)
                        .font(.system(size: 18))
                }
                .frame(width: 40, height: 40)
                .overlay(
                    Circle().stroke(post.kind.tint.opacity(0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isMine || onTapAuthor == nil)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(post.authorName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Button {
                        if !isMine { onTapAuthor?(post.authorHandle) }
                    } label: {
                        Text(post.authorHandle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isMine ? CivicTheme.quietInk : CivicTheme.violet)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .buttonStyle(.plain)
                    .disabled(isMine || onTapAuthor == nil)
                }
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(post.locality)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("·")
                        .font(.system(size: 11, weight: .bold))
                    Text(post.createdAt.socialRelativeLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(CivicTheme.mutedInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            KindBadge(kind: post.kind)

            if isMine {
                Menu {
                    Button {
                        Haptics.selection()
                        onEdit()
                    } label: {
                        Label("Edit post", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        Haptics.impact(.light)
                        onDelete()
                    } label: {
                        Label("Delete post", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
            }
        }
    }
}

private struct KindBadge: View {
    let kind: SocialPostKind

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 9, weight: .bold))
            Text(kind.label)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(kind.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(kind.tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(kind.tint.opacity(0.20), lineWidth: 1))
    }
}

// MARK: - Brief body (no fake hero image)

private struct BriefBody: View {
    let explainer: AIExplainer
    let tint: Color
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Compact title strip with confidence indicator.
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text("Athen brief")
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(tint)
                Spacer(minLength: 6)
                ConfidencePill(label: explainer.confidenceLabel, tint: tint)
            }

            // Headline as the visual hero — typographic, no fake image.
            Text(explainer.headline)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(explainer.plainEnglish)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(CivicTheme.mutedInk)
                .lineLimit(expanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)

            if needsExpansion {
                Button {
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Show less" : "Show more")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint)
                }
                .buttonStyle(.plain)
            }

            PositionsRail(positions: explainer.positions, expanded: expanded)

            NextStepBox(text: explainer.nextStep, tint: tint)

            Text(explainer.sourceLine)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CivicTheme.quietInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var needsExpansion: Bool {
        explainer.plainEnglish.count > 260
    }
}

private struct ConfidencePill: View {
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.10), in: Capsule())
    }
}

private struct PositionsRail: View {
    let positions: [ExplainerPosition]
    let expanded: Bool

    var body: some View {
        VStack(spacing: 8) {
            ForEach(positions) { position in
                PositionRow(position: position, expanded: expanded)
            }
        }
    }
}

private struct PositionRow: View {
    let position: ExplainerPosition
    let expanded: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: position.kind.systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(position.kind.tint)
                .frame(width: 22, height: 22)
                .background(position.kind.tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(position.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .lineLimit(expanded ? nil : 1)
                Text(position.summary)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineLimit(expanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: expanded)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct NextStepBox: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("NEXT STEP")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .tracking(0.5)
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .lineSpacing(2)
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Linked issue chip

private struct LinkedIssueChip: View {
    let issue: CivicIssue

    var body: some View {
        NavigationLink(value: issue.id) {
            HStack(spacing: 9) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CivicTheme.violet)
                    .frame(width: 26, height: 26)
                    .background(CivicTheme.violet.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Open issue")
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .foregroundStyle(CivicTheme.violet)
                    Text(issue.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CivicTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(CivicTheme.violet.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.violet.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action bar

private struct PostActionBar: View {
    @Environment(CivicOSStore.self) private var store
    let post: SocialPost
    let onOpenThread: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(CivicReactionKind.allCases) { kind in
                    reactionPill(kind: kind)
                }
            }
            HStack(spacing: 6) {
                actionPill(
                    title: count(store.commentCount(for: post.id)),
                    systemImage: "bubble.left",
                    tint: store.commentCount(for: post.id) > 0 ? CivicTheme.cyan : CivicTheme.mutedInk,
                    accent: store.commentCount(for: post.id) > 0
                ) {
                    Haptics.selection()
                    onOpenThread()
                }
                ShareLink(item: shareText) {
                    actionPillContent(title: count(post.shareCount), systemImage: "paperplane", tint: CivicTheme.mutedInk, accent: false)
                }
                .simultaneousGesture(TapGesture().onEnded { store.logShare(on: post.id) })
                Spacer()
                actionPill(
                    title: "Save",
                    systemImage: linkedIssue.map { store.isBookmarked($0) ? "bookmark.fill" : "bookmark" } ?? "bookmark",
                    tint: linkedIssue.map { store.isBookmarked($0) ? CivicTheme.violet : CivicTheme.mutedInk } ?? CivicTheme.mutedInk,
                    accent: linkedIssue.map { store.isBookmarked($0) } ?? false
                ) {
                    Haptics.selection()
                    if let issue = linkedIssue { store.toggleBookmark(issue) }
                }
                .opacity(linkedIssue == nil ? 0.4 : 1)
                .disabled(linkedIssue == nil)
            }
        }
    }

    @ViewBuilder
    private func reactionPill(kind: CivicReactionKind) -> some View {
        switch kind {
        case .boost:
            // Boost = amplify off-platform. Use ShareLink so the system
            // share sheet opens on tap; simultaneously log the share +
            // bump the boost counter so the social-proof signal is real.
            ShareLink(item: shareText) {
                reactionPillContent(kind: kind)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    Haptics.selection()
                    if post.myReaction != kind {
                        store.setReaction(kind, on: post.id)
                    }
                    store.logShare(on: post.id)
                }
            )
        default:
            Button {
                Haptics.selection()
                let wasMine = post.myReaction == kind
                store.setReaction(wasMine ? nil : kind, on: post.id)
                // "I'm in" = commit to act. After bumping the counter,
                // open the linked issue so the user lands where they can
                // actually do something.
                if kind == .imIn, !wasMine, let issue = linkedIssue {
                    store.pendingDeepLinkIssueID = issue.id
                }
            } label: {
                reactionPillContent(kind: kind)
            }
            .buttonStyle(.plain)
        }
    }

    private func reactionPillContent(kind: CivicReactionKind) -> some View {
        let isMine = post.myReaction == kind
        let total = post.reactions.count(kind)
        return HStack(spacing: 5) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 11, weight: .bold))
            Text(kind.shortLabel)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if total > 0 {
                Text(count(total))
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .padding(.leading, 2)
            }
        }
        .foregroundStyle(isMine ? .white : kind.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(isMine ? kind.tint : kind.tint.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(kind.tint.opacity(isMine ? 0 : 0.22), lineWidth: 1))
        .contentShape(Capsule())
    }

    private var linkedIssue: CivicIssue? {
        guard let id = post.issueID else { return nil }
        return store.issue(with: id)
    }

    private var shareText: String {
        if let issue = linkedIssue {
            return "\(post.authorName) on \(AppBrand.name): \(post.body)\n\nIssue: \(issue.title)\nathen://issue/\(issue.id.uuidString)"
        }
        return "\(post.authorName) on \(AppBrand.name): \(post.body)"
    }

    private func count(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    private func actionPill(
        title: String,
        systemImage: String,
        tint: Color,
        accent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionPillContent(title: title, systemImage: systemImage, tint: tint, accent: accent)
        }
        .buttonStyle(.plain)
    }

    private func actionPillContent(title: String, systemImage: String, tint: Color, accent: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(accent ? tint.opacity(0.10) : Color.clear, in: Capsule())
        .contentShape(Capsule())
    }
}

// MARK: - Composer (mostly unchanged, cleaned up)

private struct CreateSocialPostSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let initialIssueID: CivicIssue.ID?
    let editingPost: SocialPost?
    var initialBody: String = ""
    @State private var kind: SocialPostKind = .discussion
    @State private var bodyText = ""
    @State private var issueID: CivicIssue.ID?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var didSeedBody = false

    private var isEditing: Bool { editingPost != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        kindPicker
                        issuePicker
                        photoPicker
                        textComposer
                        postButton
                    }
                    .padding(20)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(CivicTheme.mutedInk)
                }
            }
            .task(id: selectedPhoto) {
                await loadSelectedPhoto()
            }
            .onAppear {
                if let post = editingPost {
                    kind = post.kind
                    bodyText = post.body
                    issueID = post.issueID
                    imageData = post.imageData
                } else {
                    issueID = initialIssueID
                    if !didSeedBody && bodyText.isEmpty && !initialBody.isEmpty {
                        bodyText = initialBody
                        didSeedBody = true
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isEditing ? "Edit post" : "New post")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text(isEditing
                 ? "Update what your block can see. Changes apply immediately."
                 : "Share what happened, what you filed, or what you need help understanding.")
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
        }
    }

    private var kindPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SocialPostKind.allCases) { option in
                    Button {
                        Haptics.selection()
                        kind = option
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: option.systemImage)
                                .font(.system(size: 11, weight: .bold))
                            Text(option.label)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(kind == option ? .white : option.tint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(kind == option ? option.tint : option.tint.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var issuePicker: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Attach issue", systemImage: "link")
                Picker("Attach issue", selection: $issueID) {
                    Text("No issue").tag(CivicIssue.ID?.none)
                    ForEach(store.visibleIssues) { issue in
                        Text(issue.title).tag(CivicIssue.ID?.some(issue.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(CivicTheme.cyan)
            }
        }
    }

    private var photoPicker: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Photo", systemImage: "camera.fill")

                if let imageData,
                   let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1.12, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                                .stroke(CivicTheme.hairline, lineWidth: 1)
                        )
                }

                HStack(spacing: 10) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack(spacing: 8) {
                            Image(systemName: imageData == nil ? "photo.badge.plus" : "photo")
                            Text(imageData == nil ? "Add photo" : "Change photo")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CivicTheme.cyan)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(CivicTheme.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                    }

                    if imageData != nil {
                        Button {
                            Haptics.selection()
                            imageData = nil
                            selectedPhoto = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(CivicTheme.red)
                                .frame(width: 44, height: 44)
                                .background(CivicTheme.red.opacity(0.10), in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var textComposer: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Caption", systemImage: "text.bubble.fill")
                ZStack(alignment: .topLeading) {
                    if bodyText.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 15))
                            .foregroundStyle(CivicTheme.quietInk)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                    }

                    TextEditor(text: $bodyText)
                        .font(.system(size: 15))
                        .foregroundStyle(CivicTheme.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 130)
                        .tint(CivicTheme.cyan)
                }
                .padding(10)
                .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                        .stroke(CivicTheme.hairline, lineWidth: 1)
                )
            }
        }
    }

    private var postButton: some View {
        Button {
            Haptics.success()
            if let post = editingPost {
                store.updatePost(post.id, body: bodyText, kind: kind, issueID: issueID, imageData: imageData)
            } else {
                store.createSocialPost(
                    kind: kind,
                    body: bodyText,
                    issueID: issueID,
                    imageData: imageData
                )
            }
            dismiss()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: isEditing ? "checkmark" : "paperplane.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(isEditing ? "Save changes" : "Post")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(canPost ? CivicTheme.cyan : CivicTheme.quietInk, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
            .shadow(color: (canPost ? CivicTheme.cyan : CivicTheme.quietInk).opacity(0.25), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!canPost)
    }

    private var canPost: Bool {
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageData != nil
    }

    private var placeholder: String {
        switch kind {
        case .discussion: "What's on your mind about your city?"
        case .aiBrief: "Paste an AI brief or ask Athen to draft one..."
        case .filed: "I filed because..."
        case .rally: "I asked my crew to..."
        case .event: "Council meeting Tuesday 7pm — who's in?"
        case .poll: "Ask a quick yes/no or multi-option question…"
        case .explainer: "Plain English version..."
        case .question: "Can someone help me understand..."
        }
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhoto,
              let data = try? await selectedPhoto.loadTransferable(type: Data.self)
        else { return }
        imageData = data
    }
}

private extension Date {
    var socialRelativeLabel: String {
        let interval = Date.now.timeIntervalSince(self)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

#Preview {
    SocialFeedView()
        .environment(CivicOSStore(settings: AppSettings(showSampleIssues: true, hasCompletedOnboarding: true)))
}
