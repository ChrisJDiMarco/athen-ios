import Foundation
import Observation

@MainActor
@Observable
final class CivicOSStore {
    var issues: [CivicIssue]
    var filingStatuses: [CivicIssue.ID: FilingStatus]
    var profile: UserProfile?
    var profileError: String?
    var isResolvingProfile = false

    var chatMessages: [ChatMessage] = []
    var isChatStreaming = false
    var chatError: String?
    var pendingAssistantPrompt: String?
    var pendingSocialIssueID: CivicIssue.ID?

    var groups: [OutreachGroup] = []
    var groupLetters: [GroupLetter] = []
    var socialPosts: [SocialPost] = []
    var services: [CivicService] = CivicService.samples
    var isRefreshingAthenBriefs = false
    var lastAthenBriefRefreshError: String?

    var backgroundByIssue: [CivicIssue.ID: BackgroundReading] = [:]
    var loadingBackgroundFor: Set<CivicIssue.ID> = []

    var pendingDeepLinkIssueID: CivicIssue.ID?
    var pendingFeedOpen = false
    var pendingHelpOpen = false

    var settings: AppSettings
    var isRefreshingIssues = false
    var lastIssueRefreshError: String?
    var lastIssueRefreshAt: Date?
    var civicBrief: CivicBrief?

    var bookmarkedIssueIDs: Set<CivicIssue.ID> = []

    var backendStatus: BackendStatus = .unknown
    var isCheckingBackend = false

    var sourcesSnapshot: CivicSourcesSnapshot?
    var isRefreshingSources = false
    var lastSourcesError: String?

    var lastRefreshReport: RefreshReport?
    var isRunningOrchestrator = false
    var lastOrchestratorError: String?

    var briefDigest: CivicBriefDigest?
    var briefAnalyses: [String: CivicBriefAnalysis] = [:]
    var isLoadingBriefDigest = false
    var lastBriefError: String?
    var generatingBriefFor: Set<String> = []

    var audioBriefing: CivicAudioBriefing?
    var isGeneratingAudioBriefing = false
    var lastAudioBriefingError: String?
    /// Listener-controllable customization. Stored vars (so @Observable
    /// actually tracks reads + writes, and SwiftUI re-renders selection
    /// chips immediately) with `didSet` that mirrors to UserDefaults for
    /// cross-launch persistence. Default values match the original 5-min
    /// Sarah behavior, so existing callers get the same experience.
    var audioBriefingDurationMin: Int = UserDefaults.standard.object(forKey: "athen.audioBriefing.duration") as? Int ?? 5 {
        didSet { UserDefaults.standard.set(audioBriefingDurationMin, forKey: "athen.audioBriefing.duration") }
    }
    var audioBriefingVoiceId: String? = UserDefaults.standard.string(forKey: "athen.audioBriefing.voiceId") {
        didSet {
            if let v = audioBriefingVoiceId, !v.isEmpty {
                UserDefaults.standard.set(v, forKey: "athen.audioBriefing.voiceId")
            } else {
                UserDefaults.standard.removeObject(forKey: "athen.audioBriefing.voiceId")
            }
        }
    }
    var audioBriefingFocus: String = UserDefaults.standard.string(forKey: "athen.audioBriefing.focus") ?? "" {
        didSet { UserDefaults.standard.set(audioBriefingFocus, forKey: "athen.audioBriefing.focus") }
    }
    /// When the ambient monitor decides it's morning + AirPods/CarPlay are
    /// online + opt-in is set, it bumps this counter. The AudioBriefingCard
    /// listens on it and starts playback.
    var ambientPlayRequestID: Int = 0

    // MARK: - Life-event plans
    var lifeEventPlans: [CivicLifeEventPlan] = []
    var isGeneratingLifeEventPlan: Bool = false
    var lastLifeEventError: String?

    // MARK: - Officials directory
    var federalDirectory: [DirectoryOfficial] = []
    var stateDirectoryByCode: [String: [DirectoryOfficial]] = [:]
    var isLoadingDirectory: Bool = false
    var lastDirectoryError: String?
    var bookmarkedOfficialIDs: Set<String> = []

    // MARK: - Petitions
    var petitions: [CivicPetition] = []
    var petitionStats: CivicPetitionListResponse.Stats?
    var signedPetitionIDs: Set<String> = []
    var createdPetitionIDs: Set<String> = []
    var isLoadingPetitions: Bool = false
    var lastPetitionError: String?
    /// Local filter state for the petitions browse view.
    var petitionFilter: PetitionFilter = .openOnly

    // MARK: - Integrations (Composio)
    var integrationCatalog: [CivicIntegrationApp] = []
    var integrationSettings: CivicIntegrationSettings = .default
    var integrationStatusByApp: [String: CivicIntegrationStatus] = [:]
    var isLoadingIntegrations: Bool = false
    var integrationsError: String?
    /// Stable per-install identifier passed to Composio as the entity id so
    /// connections persist across sessions. Generated on first launch.
    var integrationEntityID: String = ""

    var draftVariants: [CivicIssue.ID: [DraftToneVariant]] = [:]
    var generatingVariantsFor: Set<CivicIssue.ID> = []
    var lastVariantError: String?

    /// All comments indexed by their parent post id. Persisted alongside
    /// social posts so threads survive launches.
    var commentsByPost: [SocialPost.ID: [CivicComment]] = [:]

    /// Last-seen content of each bookmarked bill — the diff watcher compares
    /// fresh issue payloads against these snapshots on every refresh.
    var bookmarkSnapshots: [UUID: BookmarkSnapshot] = [:]
    /// Detected changes on bookmarked bills since the user last cleared them.
    /// Newest first.
    var diffEvents: [CivicDiffEvent] = []

    /// Number of consecutive calendar days the user has opened Athen.
    var civicStreakDays: Int = 0
    /// Last calendar day the user opened the app (YYYY-MM-DD UTC).
    var lastOpenedDay: String?
    /// Stored `Date` of the last launch — used by the "what's new since last
    /// visit" card to scope its content window.
    var lastOpenedAt: Date?
    /// Snapshot of the last time the streak was incremented for UI affordances.
    var previousLastOpenedAt: Date?

    /// In-app notifications inbox. Bell icon in Home shows unread count.
    /// Newest first. Capped at 100 entries — older ones drop off the tail.
    var inboxNotifications: [AthenInboxNotification] = []

    /// Server-side saved searches with optional alerts. Reporters track
    /// keywords / Hill staff track reps / citizens track personal issues.
    /// Loaded lazily via `loadSavedSearches()` and refreshed after any
    /// create/update/delete.
    var savedSearches: [CivicSavedSearch] = []
    var isLoadingSavedSearches: Bool = false
    var lastSavedSearchError: String?

    /// Pending "Undo Send" handles by issue id. When the toast times out
    /// (~5s), the dispatcher fires; if the user taps Undo first, we just
    /// drop the entry.
    var pendingSends: [CivicIssue.ID: PendingSendHandle] = [:]

    struct PendingSendHandle: Hashable {
        let issueID: CivicIssue.ID
        let issueTitle: String
        let draft: DraftedFiling
        let expiresAt: Date
    }

    private var chatTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    private var filingService: CivicFilingServicing
    private var profileResolver: ProfileResolverServicing
    private var chatService: ChatServicing
    private var newsService: NewsServicing
    private var issueService: IssueServicing
    private var athenBriefService: AthenBriefServicing
    private var voiceService: VoiceServicing
    private var sourcesService: SourcesServicing
    private var refreshService: RefreshServicing
    private var briefService: BriefServicing
    private var draftVariantsService: DraftVariantsServicing
    private var ballotService: BallotServicing
    private var integrationsService: IntegrationsServicing
    private var petitionsService: PetitionsServicing
    private var voterRailService: VoterRailServicing
    private var lifeEventsService: LifeEventsServicing
    private var directoryService: OfficialsDirectoryServicing
    private(set) var speechService: SpeechServicing
    private(set) var moderationService: ModerationServicing
    private(set) var savedSearchService: SavedSearchServicing
    private(set) var timelineService: TimelineServicing
    private(set) var urlAnalyzeService: UrlAnalyzeServicing
    private(set) var personalImpactService: PersonalImpactServicing
    private let ambientMonitor: AmbientBriefingMonitor
    private let defaults: UserDefaults

    private static let profileDefaultsKey = "civic-os.profile.v1"
    private static let groupsDefaultsKey = "civic-os.groups.v1"
    private static let settingsDefaultsKey = "civic-os.settings.v1"
    private static let bookmarksDefaultsKey = "civic-os.bookmarks.v1"
    private static let socialPostsDefaultsKey = "civic-os.social-posts.v1"
    private static let commentsDefaultsKey = "civic-os.comments.v1"
    private static let filingStatusesDefaultsKey = "civic-os.filing-statuses.v1"
    private static let bookmarkSnapshotsKey = "athen.bookmark-snapshots.v1"
    private static let diffEventsKey = "athen.diff-events.v1"
    private static let groupLettersKey = "athen.group-letters.v1"
    private static let integrationEntityKey = "athen.integration-entity-id.v1"
    private static let gmailFilingEnabledKey = "athen.gmail-filing-enabled.v1"
    private static let lifeEventPlansKey = "athen.life-event-plans.v1"
    private static let integrationSettingsKey = "athen.integration-settings.v1"
    private static let bookmarkedOfficialsKey = "athen.bookmarked-officials.v1"
    private static let streakKey = "athen.streak.v1"
    private static let lastOpenedAtKey = "athen.last-opened-at.v1"
    private static let inboxKey = "athen.inbox.v1"

    init(
        issues: [CivicIssue]? = nil,
        filingStatuses: [CivicIssue.ID: FilingStatus] = [:],
        filingService: CivicFilingServicing = CivicOSStore.defaultFilingService(),
        profileResolver: ProfileResolverServicing = CivicOSStore.defaultProfileResolver(),
        chatService: ChatServicing = CivicOSStore.defaultChatService(),
        newsService: NewsServicing = CivicOSStore.defaultNewsService(),
        issueService: IssueServicing = CivicOSStore.defaultIssueService(),
        athenBriefService: AthenBriefServicing = CivicOSStore.defaultAthenBriefService(),
        voiceService: VoiceServicing = CivicOSStore.defaultVoiceService(),
        sourcesService: SourcesServicing = CivicOSStore.defaultSourcesService(),
        refreshService: RefreshServicing = CivicOSStore.defaultRefreshService(),
        briefService: BriefServicing = CivicOSStore.defaultBriefService(),
        draftVariantsService: DraftVariantsServicing = CivicOSStore.defaultDraftVariantsService(),
        ballotService: BallotServicing = CivicOSStore.defaultBallotService(),
        integrationsService: IntegrationsServicing = CivicOSStore.defaultIntegrationsService(),
        petitionsService: PetitionsServicing = CivicOSStore.defaultPetitionsService(),
        voterRailService: VoterRailServicing = CivicOSStore.defaultVoterRailService(),
        lifeEventsService: LifeEventsServicing = CivicOSStore.defaultLifeEventsService(),
        directoryService: OfficialsDirectoryServicing = CivicOSStore.defaultDirectoryService(),
        speechService: SpeechServicing = CivicOSStore.defaultSpeechService(),
        moderationService: ModerationServicing = CivicOSStore.defaultModerationService(),
        savedSearchService: SavedSearchServicing = CivicOSStore.defaultSavedSearchService(),
        timelineService: TimelineServicing = CivicOSStore.defaultTimelineService(),
        urlAnalyzeService: UrlAnalyzeServicing = CivicOSStore.defaultUrlAnalyzeService(),
        personalImpactService: PersonalImpactServicing = CivicOSStore.defaultPersonalImpactService(),
        defaults: UserDefaults = .standard,
        loadPersistedProfile: Bool = true,
        settings: AppSettings? = nil
    ) {
        self.filingStatuses = filingStatuses
        self.filingService = filingService
        self.profileResolver = profileResolver
        self.chatService = chatService
        self.newsService = newsService
        self.issueService = issueService
        self.athenBriefService = athenBriefService
        self.voiceService = voiceService
        self.sourcesService = sourcesService
        self.refreshService = refreshService
        self.briefService = briefService
        self.draftVariantsService = draftVariantsService
        self.ballotService = ballotService
        self.integrationsService = integrationsService
        self.petitionsService = petitionsService
        self.voterRailService = voterRailService
        self.lifeEventsService = lifeEventsService
        self.directoryService = directoryService
        self.speechService = speechService
        self.moderationService = moderationService
        self.savedSearchService = savedSearchService
        self.timelineService = timelineService
        self.urlAnalyzeService = urlAnalyzeService
        self.personalImpactService = personalImpactService
        self.ambientMonitor = AmbientBriefingMonitor(defaults: defaults)
        self.defaults = defaults
        // Bootstrap a stable per-install entity id for Composio. Stored once;
        // never regenerated — losing it would orphan the user's connections.
        if let existing = defaults.string(forKey: Self.integrationEntityKey), !existing.isEmpty {
            self.integrationEntityID = existing
        } else {
            let fresh = UUID().uuidString
            defaults.set(fresh, forKey: Self.integrationEntityKey)
            self.integrationEntityID = fresh
        }

        var loadedSettings: AppSettings
        if let settings {
            loadedSettings = settings
        } else if let data = defaults.data(forKey: Self.settingsDefaultsKey),
                  let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            loadedSettings = saved
        } else {
            loadedSettings = .default
        }
        // Demo mode is dead. Force-heal anyone whose persisted settings still
        // have it on so the next launch shows real civic items (or an empty
        // feed) instead of bundled MockCivicData.
        if loadedSettings.showSampleIssues {
            loadedSettings.showSampleIssues = false
        }
        self.settings = loadedSettings

        if let issues {
            self.issues = issues
        } else {
            self.issues = []
        }

        if loadPersistedProfile,
           let data = defaults.data(forKey: Self.profileDefaultsKey),
           let saved = try? JSONDecoder().decode(UserProfile.self, from: data)
        {
            self.profile = saved
        }

        if loadPersistedProfile,
           let data = defaults.data(forKey: Self.groupsDefaultsKey),
           let saved = try? JSONDecoder().decode([OutreachGroup].self, from: data)
        {
            self.groups = saved
        }

        if loadPersistedProfile,
           let data = defaults.data(forKey: Self.bookmarksDefaultsKey),
           let saved = try? JSONDecoder().decode([UUID].self, from: data)
        {
            self.bookmarkedIssueIDs = Set(saved)
        }

        if loadPersistedProfile,
           let data = defaults.data(forKey: Self.socialPostsDefaultsKey),
           let saved = try? JSONDecoder().decode([SocialPost].self, from: data)
        {
            // Square is social-only now; AI briefs live in the Brief tab.
            // Prune legacy persisted aiBrief posts AND the old fake-persona
            // seed posts so old installs see a clean community.
            let fakeSeedHandles: Set<String> = ["@maya.phl", "@blockcaptain", "@ariasks", "@nora.energy"]
            let pruned = saved.filter { $0.kind != .aiBrief && !fakeSeedHandles.contains($0.authorHandle) }
            self.socialPosts = pruned
            if pruned.count != saved.count {
                if let data = try? JSONEncoder().encode(pruned) {
                    defaults.set(data, forKey: Self.socialPostsDefaultsKey)
                }
            }
        } else {
            // Fresh install: start with an empty Square — let real activity
            // populate it. (No more fake personas.)
            self.socialPosts = []
        }

        if loadPersistedProfile,
           let data = defaults.data(forKey: Self.commentsDefaultsKey),
           let saved = try? JSONDecoder().decode([SocialPost.ID: [CivicComment]].self, from: data)
        {
            self.commentsByPost = saved
        }

        if loadPersistedProfile,
           filingStatuses.isEmpty,
           let data = defaults.data(forKey: Self.filingStatusesDefaultsKey),
           let saved = try? JSONDecoder().decode([CivicIssue.ID: FilingReceipt].self, from: data)
        {
            // We only persist sent receipts; drafting/sending/failed are
            // transient session state and should reset on launch.
            self.filingStatuses = saved.mapValues { FilingStatus.sent($0) }
        }

        if loadPersistedProfile,
           let data = defaults.data(forKey: Self.bookmarkSnapshotsKey),
           let saved = try? JSONDecoder().decode([UUID: BookmarkSnapshot].self, from: data)
        {
            self.bookmarkSnapshots = saved
        }
        if loadPersistedProfile,
           let data = defaults.data(forKey: Self.diffEventsKey),
           let saved = try? JSONDecoder().decode([CivicDiffEvent].self, from: data)
        {
            self.diffEvents = saved
        }
        if loadPersistedProfile,
           let data = defaults.data(forKey: Self.groupLettersKey),
           let saved = try? JSONDecoder().decode([GroupLetter].self, from: data)
        {
            self.groupLetters = saved
        }
        if loadPersistedProfile,
           let data = defaults.data(forKey: Self.lifeEventPlansKey),
           let saved = try? JSONDecoder().decode([CivicLifeEventPlan].self, from: data)
        {
            self.lifeEventPlans = saved
        }
        if loadPersistedProfile,
           let data = defaults.data(forKey: Self.integrationSettingsKey),
           let saved = try? JSONDecoder().decode(CivicIntegrationSettings.self, from: data)
        {
            self.integrationSettings = saved
        }
        if loadPersistedProfile,
           let data = defaults.data(forKey: Self.bookmarkedOfficialsKey),
           let saved = try? JSONDecoder().decode([String].self, from: data)
        {
            self.bookmarkedOfficialIDs = Set(saved)
        }
        if loadPersistedProfile,
           let data = defaults.data(forKey: Self.streakKey),
           let saved = try? JSONDecoder().decode(StreakSnapshot.self, from: data)
        {
            self.civicStreakDays = saved.days
            self.lastOpenedDay = saved.lastOpenedDay
        }
        if loadPersistedProfile,
           let raw = defaults.object(forKey: Self.lastOpenedAtKey) as? Date
        {
            self.previousLastOpenedAt = raw
            self.lastOpenedAt = raw
        }
        if loadPersistedProfile,
           let data = defaults.data(forKey: Self.inboxKey),
           let saved = try? JSONDecoder().decode([AthenInboxNotification].self, from: data)
        {
            self.inboxNotifications = saved
        }

        if loadPersistedProfile {
            loadModerationFromDefaults()
        }

        // If the user set a backend URL in Settings, swap the HTTP services in
        // now so the very first request after launch hits the real backend.
        if let urlString = loadedSettings.backendURL,
           let url = URL(string: urlString),
           !urlString.isEmpty
        {
            self.filingService = HTTPCivicFilingService(baseURL: url)
            self.profileResolver = HTTPProfileResolverService(baseURL: url)
            self.chatService = HTTPChatService(baseURL: url)
            self.newsService = HTTPNewsService(baseURL: url)
            self.issueService = HTTPIssueService(baseURL: url)
            self.athenBriefService = HTTPAthenBriefService(baseURL: url)
            self.voiceService = HTTPVoiceService(baseURL: url)
            self.sourcesService = HTTPSourcesService(baseURL: url)
            self.refreshService = HTTPRefreshService(baseURL: url)
            self.briefService = HTTPBriefService(baseURL: url)
            self.draftVariantsService = HTTPDraftVariantsService(baseURL: url)
            self.ballotService = HTTPBallotService(baseURL: url)
            self.integrationsService = HTTPIntegrationsService(baseURL: url)
            self.petitionsService = HTTPPetitionsService(baseURL: url)
            self.voterRailService = HTTPVoterRailService(baseURL: url)
            self.lifeEventsService = HTTPLifeEventsService(baseURL: url)
            self.directoryService = HTTPOfficialsDirectoryService(baseURL: url)
            self.speechService = HTTPSpeechService(baseURL: url)
            self.moderationService = HTTPModerationService(baseURL: url)
            self.savedSearchService = HTTPSavedSearchService(baseURL: url)
            self.timelineService = HTTPTimelineService(baseURL: url)
            self.urlAnalyzeService = HTTPUrlAnalyzeService(baseURL: url)
            self.personalImpactService = HTTPPersonalImpactService(baseURL: url)
        }
    }

    var sentCount: Int {
        filingStatuses.values.filter(\.isSent).count
    }

    var pendingReplies: Int {
        issues.filter { $0.reply != nil }.count
    }

    var visibleIssues: [CivicIssue] {
        let interests = profile?.interests ?? []
        let hiddenHosts = disabledSourceHosts
        let hyperlocal = settings.hyperlocalMode
        return issues.filter { issue in
            guard issue.scope.matches(profile: profile) else { return false }
            if isIssueFromDisabledSource(issue, hiddenHosts: hiddenHosts) { return false }
            // Hyperlocal mode hides federal items so the feed is city/state only.
            if hyperlocal, case .federal = issue.scope { return false }
            if interests.isEmpty { return true }
            // Federal items always show — they affect everyone.
            if case .federal = issue.scope { return true }
            if issue.topics.isEmpty { return true }
            return !issue.topics.isDisjoint(with: interests)
        }
    }

    /// Hosts belonging to sources the user has switched off in the Sources panel.
    private var disabledSourceHosts: Set<String> {
        guard let snapshot = sourcesSnapshot else { return [] }
        let disabledIDs = settings.disabledSourceIDs
        guard !disabledIDs.isEmpty else { return [] }
        return Set(snapshot.sources
            .filter { disabledIDs.contains($0.id) }
            .flatMap { $0.allowedHosts.map { $0.lowercased() } })
    }

    private func isIssueFromDisabledSource(_ issue: CivicIssue, hiddenHosts: Set<String>) -> Bool {
        guard !hiddenHosts.isEmpty else { return false }
        let candidates: [String] = [
            issue.sourceHost?.lowercased(),
            issue.sourceURLValue?.host?.replacingOccurrences(of: "www.", with: "").lowercased()
        ].compactMap { $0 }
        return candidates.contains { host in
            hiddenHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
        }
    }

    var prioritizedIssues: [CivicIssue] {
        let interests = profile?.interests ?? []
        return visibleIssues.sorted { lhs, rhs in
            let lhsMatch = lhs.topics.isDisjoint(with: interests) ? 1 : 0
            let rhsMatch = rhs.topics.isDisjoint(with: interests) ? 1 : 0
            if lhsMatch != rhsMatch { return lhsMatch < rhsMatch }
            return lhs.voteDate < rhs.voteDate
        }
    }

    var localIssues: [CivicIssue] {
        issues.filter {
            if case .localPhilly = $0.scope { return true }
            return false
        }
    }

    var hasLocalIssues: Bool {
        visibleIssues.contains {
            if case .localPhilly = $0.scope { return true }
            return false
        }
    }

    func issue(with id: CivicIssue.ID) -> CivicIssue? {
        issues.first { $0.id == id }
    }

    func status(for issue: CivicIssue) -> FilingStatus {
        filingStatuses[issue.id] ?? .ready
    }

    var displayAddress: String {
        profile?.displayLocation ?? "Set your ZIP to get started"
    }

    var displayDistrict: String {
        if let profile, let district = profile.congressionalDistrict {
            return district
        }
        if let local = profile?.officials.local.first {
            return local.district ?? local.name
        }
        return profile?.stateName ?? "—"
    }

    /// Begin the AI draft. Doesn't send. Returns the draft for the sheet to display.
    func beginDraft(_ action: CivicAction, for issue: CivicIssue) async -> DraftedFiling? {
        // A stale .failed status from a prior attempt shouldn't block a retry —
        // only block on truly in-flight states.
        if status(for: issue).isBusy { return nil }
        guard let profile else {
            filingStatuses[issue.id] = .failed("Set your ZIP from Radar → profile first — we need it to find your representative.")
            return nil
        }

        filingStatuses[issue.id] = .drafting(action)
        do {
            let draft = try await filingService.draft(action, for: issue, from: profile.zipCode)
            // Defensive: backend bug could return a blank body. Treat that as a
            // failure so the sheet shows an error instead of an empty editor.
            guard !draft.message.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                filingStatuses[issue.id] = .failed("Athen drafted an empty message. Try again.")
                return nil
            }
            filingStatuses[issue.id] = .ready
            return draft
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? (error as? CivicFilingError)?.errorDescription
                ?? "Couldn't reach the backend to draft your message."
            filingStatuses[issue.id] = .failed(message)
            return nil
        }
    }

    /// Reset a stale `.failed` status so a retry can proceed cleanly.
    func clearFilingFailure(for issue: CivicIssue) {
        if case .failed = filingStatuses[issue.id] {
            filingStatuses[issue.id] = .ready
        }
    }

    /// Confirm a draft. Behavior depends on what the user has connected:
    ///
    /// 1. **User's Gmail connected via Composio** → attempts a real email through
    ///    the user's own account. On any failure, falls back to recorded-local
    ///    so the user never sees a silent loss.
    /// 2. **Otherwise** → records the filing locally with channel
    ///    `.recordedLocal`. The receipt is honest: "Recorded in your history.
    ///    Direct delivery to officials is rolling out soon." No fake "sent" UX.
    ///
    /// This is the v1 public-beta behavior. Once Postmark + a verified sending
    /// domain are wired, the else-branch will go through the backend dispatcher.
    func confirmSend(_ draft: DraftedFiling) async {
        guard !status(for: draft.issue).isBusy else { return }
        filingStatuses[draft.issue.id] = .sending(draft.action)

        if isGmailFilingEnabled && isGmailConnected {
            do {
                let receipt = try await filingService.send(draft)
                filingStatuses[draft.issue.id] = .sent(receipt)
                persistFilingStatuses()
                onFilingSent(issue: draft.issue, action: draft.action, receipt: receipt)
                return
            } catch {
                // Gmail send failed — fall through to recorded-local so the
                // user keeps the record, with a status note explaining why.
                let receipt = recordedLocalReceipt(
                    for: draft,
                    note: "Could not reach Gmail — recorded in your history. Try again later."
                )
                filingStatuses[draft.issue.id] = .sent(receipt)
                persistFilingStatuses()
                onFilingSent(issue: draft.issue, action: draft.action, receipt: receipt)
                return
            }
        }

        // No Gmail connected — record locally only.
        let receipt = recordedLocalReceipt(for: draft, note: "Recorded in your history. Direct delivery to officials is rolling out in a later release.")
        filingStatuses[draft.issue.id] = .sent(receipt)
        persistFilingStatuses()
        onFilingSent(issue: draft.issue, action: draft.action, receipt: receipt)
    }

    private func recordedLocalReceipt(for draft: DraftedFiling, note: String) -> FilingReceipt {
        FilingReceipt(
            action: draft.action,
            sentAt: .now,
            officialName: draft.official.name,
            confirmationCode: "REC-\(UUID().uuidString.prefix(8))",
            messagePreview: String(draft.message.body.prefix(220)),
            channel: .recordedLocal,
            statusNote: note,
            queued: true,
            dryRun: false
        )
    }

    /// Legacy one-tap path. Drafts + sends in a single call without user review.
    /// Kept for tests + previews; production UI should use beginDraft → confirmSend.
    func submit(_ action: CivicAction, for issue: CivicIssue) async {
        guard let draft = await beginDraft(action, for: issue) else { return }
        await confirmSend(draft)
    }

    func updateZip(_ rawZip: String) async {
        let zip = rawZip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard zip.count >= 5 else {
            profileError = "Enter a 5-digit ZIP."
            return
        }

        isResolvingProfile = true
        profileError = nil
        defer { isResolvingProfile = false }

        let priorZip = profile?.zipCode

        do {
            let resolved = try await profileResolver.resolve(zip: zip)
            profile = resolved
            persist(resolved)
            Haptics.success()

            // ZIP changed → all cached results that depended on the old ZIP
            // are now stale. Invalidate them so each tab re-fetches the
            // moment the user lands on it, and kick off the most important
            // refreshes in the background right now.
            if priorZip != zip {
                invalidateZipDependentCaches()
            }
        } catch {
            profileError = (error as? LocalizedError)?.errorDescription ?? "Could not look up that ZIP."
            Haptics.error()
        }
    }

    /// Wipes any cached state that depended on the old ZIP / state so each
    /// tab re-fetches on next visit. Also flags `zipChangedNeedsRefresh` so
    /// surfaces can show a soft "refresh needed" banner if the auto-refetch
    /// hasn't completed yet.
    var zipChangedNeedsRefresh: Bool = false

    private func invalidateZipDependentCaches() {
        zipChangedNeedsRefresh = true
        civicBrief = nil
        briefDigest = nil
        briefAnalyses = [:]
        sourcesSnapshot = nil
        upcomingElections = []
        pollingPlaceInfo = nil
        sampleBallotResponse = nil
        registrationInfo = nil
        repScorecard = nil
        audioBriefing = nil
        AudioBriefingPlayer.shared.stop()

        // Background refreshes — happen in parallel so each tab is ready
        // when the user opens it next.
        Task { await refreshIssues() }
        Task { await loadBriefDigest(warm: false) }
        Task { await loadVoterRail() }
        Task { await refreshSources() }
    }

    /// Called by views that have honored the "ZIP changed" flag (e.g., after
    /// completing a fresh load).
    func acknowledgeZipRefresh() {
        zipChangedNeedsRefresh = false
    }

    func clearProfile() {
        profile = nil
        defaults.removeObject(forKey: Self.profileDefaultsKey)
    }

    /// Apple Guideline 5.1.1(v): full account/data deletion path.
    ///
    /// 1. Fires `DELETE /v1/data` so the backend scrubs records keyed by this
    ///    install (petition signatures + moderation reports). Best-effort —
    ///    a network failure does NOT block local wipe.
    /// 2. Wipes every UserDefaults key the app owns, in-memory state, and any
    ///    persisted caches. Onboarding is reset so the user lands back on the
    ///    welcome flow.
    /// Idempotent — safe to call twice.
    @MainActor
    func deleteAllData() async {
        // 1) Backend scrub (best-effort, non-blocking).
        await scrubBackend()

        // 2) In-memory state — reset to install-fresh values.
        profile = nil
        issues = []
        filingStatuses = [:]
        bookmarkedIssueIDs = []
        bookmarkedOfficialIDs = []
        socialPosts = []
        commentsByPost = [:]
        blockedAuthors = []
        reportedPostIDs = []
        savedPostIDs = []
        mutedThreadIDs = []
        bookmarkSnapshots = [:]
        diffEvents = []
        groups = []
        groupLetters = []
        lifeEventPlans = []
        integrationSettings = .default
        civicStreakDays = 0
        lastOpenedDay = nil
        previousLastOpenedAt = nil
        inboxNotifications = []
        settings = AppSettings()

        // 3) UserDefaults wipe — every key the store writes to.
        let keys: [String] = [
            Self.profileDefaultsKey,
            Self.groupsDefaultsKey,
            Self.settingsDefaultsKey,
            Self.bookmarksDefaultsKey,
            Self.socialPostsDefaultsKey,
            Self.commentsDefaultsKey,
            Self.filingStatusesDefaultsKey,
            Self.bookmarkSnapshotsKey,
            Self.diffEventsKey,
            Self.groupLettersKey,
            Self.integrationEntityKey,
            Self.gmailFilingEnabledKey,
            Self.lifeEventPlansKey,
            Self.integrationSettingsKey,
            Self.bookmarkedOfficialsKey,
            Self.streakKey,
            Self.lastOpenedAtKey,
            Self.blockedAuthorsKey,
            Self.reportedPostsKey,
            Self.savedPostsKey,
            Self.mutedThreadsKey,
            Self.inboxKey,
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }

        // 4) Rebuild the auth-injecting session so the next request has no
        //    install header (a new install ID will mint on next onboarding).
        AthenURLSession.refresh()
    }

    private func scrubBackend() async {
        guard let baseURL = Self.configuredBaseURL() else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/data"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = 15
        do {
            _ = try await AthenURLSession.shared.data(for: request)
        } catch {
            // Non-fatal — local wipe still proceeds.
        }
    }

    // MARK: - Interests

    func setInterests(_ interests: Set<CivicTopic>) {
        guard var current = profile else { return }
        current.interests = interests
        profile = current
        persist(current)
        Task { await rescheduleNotifications() }
    }

    func setFactors(_ factors: Set<CivicProfileFactor>) {
        guard var current = profile else { return }
        current.factors = factors
        profile = current
        persist(current)
    }

    // MARK: - Groups

    func addGroup(_ group: OutreachGroup) {
        groups.append(group)
        persistGroups()
    }

    func renameGroup(_ id: OutreachGroup.ID, name: String, emoji: String) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].name = name
        groups[idx].emoji = emoji
        persistGroups()
    }

    func deleteGroup(_ id: OutreachGroup.ID) {
        groups.removeAll { $0.id == id }
        persistGroups()
    }

    func addMember(_ member: GroupMember, to groupID: OutreachGroup.ID) {
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[idx].members.append(member)
        persistGroups()
    }

    func removeMember(_ memberID: GroupMember.ID, from groupID: OutreachGroup.ID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[gIdx].members.removeAll { $0.id == memberID }
        persistGroups()
    }

    func logRally(memberID: GroupMember.ID, groupID: OutreachGroup.ID, issue: CivicIssue) {
        guard
            let gIdx = groups.firstIndex(where: { $0.id == groupID }),
            let mIdx = groups[gIdx].members.firstIndex(where: { $0.id == memberID })
        else { return }
        let event = RallyEvent(issueID: issue.id, issueTitle: issue.title)
        groups[gIdx].members[mIdx].rallyEvents.append(event)
        persistGroups()
    }

    func rallyCount(for issue: CivicIssue) -> Int {
        groups.reduce(0) { total, group in
            total + group.members.filter { member in
                member.rallyEvents.contains { $0.issueID == issue.id }
            }.count
        }
    }

    func memberHasRallied(_ memberID: GroupMember.ID, in groupID: OutreachGroup.ID, for issue: CivicIssue) -> Bool {
        guard
            let group = groups.first(where: { $0.id == groupID }),
            let member = group.members.first(where: { $0.id == memberID })
        else { return false }
        return member.rallyEvents.contains { $0.issueID == issue.id }
    }

    func group(with id: OutreachGroup.ID) -> OutreachGroup? {
        groups.first { $0.id == id }
    }

    private func persistGroups() {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        defaults.set(data, forKey: Self.groupsDefaultsKey)
    }

    // MARK: - Group letters

    func letters(for groupID: OutreachGroup.ID) -> [GroupLetter] {
        groupLetters.filter { $0.groupID == groupID }.sorted { $0.createdAt > $1.createdAt }
    }

    func updateGroupLetter(_ letterID: GroupLetter.ID, subject: String, body: String) {
        guard let idx = groupLetters.firstIndex(where: { $0.id == letterID }) else { return }
        groupLetters[idx].subject = subject
        groupLetters[idx].body = body
        persistGroupLetters()
    }

    func startGroupLetter(group: OutreachGroup, issue: CivicIssue, subject: String, body: String) -> GroupLetter {
        let firstSigner = GroupLetterSigner(memberID: nil, name: "You")
        let letter = GroupLetter(
            groupID: group.id,
            issueID: issue.id,
            issueTitle: issue.title,
            subject: subject,
            body: body,
            signers: [firstSigner]
        )
        groupLetters.insert(letter, at: 0)
        persistGroupLetters()
        return letter
    }

    func signGroupLetter(_ letterID: GroupLetter.ID, member: GroupMember) {
        guard let idx = groupLetters.firstIndex(where: { $0.id == letterID }) else { return }
        // Don't double-sign the same member.
        if groupLetters[idx].signers.contains(where: { $0.memberID == member.id }) { return }
        let signer = GroupLetterSigner(memberID: member.id, name: member.name)
        groupLetters[idx].signers.append(signer)
        persistGroupLetters()
    }

    func removeGroupLetterSigner(_ letterID: GroupLetter.ID, signerID: GroupLetterSigner.ID) {
        guard let idx = groupLetters.firstIndex(where: { $0.id == letterID }) else { return }
        groupLetters[idx].signers.removeAll { $0.id == signerID }
        // If the originator removed themselves and the letter is empty, delete it.
        if groupLetters[idx].signers.isEmpty {
            groupLetters.remove(at: idx)
        }
        persistGroupLetters()
    }

    func markGroupLetterSent(_ letterID: GroupLetter.ID) {
        guard let idx = groupLetters.firstIndex(where: { $0.id == letterID }) else { return }
        groupLetters[idx].sentAt = .now
        persistGroupLetters()
        // Fire Slack / Discord automations if configured.
        onGroupLetterSent(groupLetters[idx])
    }

    func deleteGroupLetter(_ letterID: GroupLetter.ID) {
        groupLetters.removeAll { $0.id == letterID }
        persistGroupLetters()
    }

    private func persistGroupLetters() {
        guard let data = try? JSONEncoder().encode(groupLetters) else { return }
        defaults.set(data, forKey: Self.groupLettersKey)
    }

    // MARK: - Social feed

    var sortedSocialPosts: [SocialPost] {
        visibleSocialPosts.sorted { $0.createdAt > $1.createdAt }
    }

    var socialActionCount: Int {
        socialPosts.filter { $0.kind == .filed || $0.kind == .rally }.count
    }

    func createSocialPost(
        kind: SocialPostKind,
        body: String,
        issueID: CivicIssue.ID?,
        imageData: Data?
    ) {
        let issue = issueID.flatMap { self.issue(with: $0) }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || imageData != nil else { return }

        let profileLocation = profile?.localityLabel ?? profile?.stateName ?? AppBrand.name
        let post = SocialPost(
            authorName: "You",
            authorHandle: "@you",
            authorEmoji: "🙂",
            body: trimmed.isEmpty ? defaultSocialCaption(kind: kind, issue: issue) : trimmed,
            kind: kind,
            issueID: issue?.id,
            issueTitle: issue?.title,
            locality: profileLocation,
            imageData: imageData,
            likeCount: 0,
            commentCount: 0,
            shareCount: 0
        )

        socialPosts.insert(post, at: 0)
        persistSocialPosts()
    }

    func toggleLike(on postID: SocialPost.ID) {
        guard let idx = socialPosts.firstIndex(where: { $0.id == postID }) else { return }
        socialPosts[idx].likedByMe.toggle()
        socialPosts[idx].likeCount += socialPosts[idx].likedByMe ? 1 : -1
        socialPosts[idx].likeCount = max(0, socialPosts[idx].likeCount)
        persistSocialPosts()
    }

    /// Set or clear a civic reaction on a post. Tapping the same reaction
    /// twice clears it. Tapping a different reaction swaps from the previous.
    func setReaction(_ kind: CivicReactionKind?, on postID: SocialPost.ID) {
        guard let idx = socialPosts.firstIndex(where: { $0.id == postID }) else { return }
        var post = socialPosts[idx]
        let previous = post.myReaction
        if let previous {
            decrement(&post.reactions, kind: previous)
        }
        if let kind, previous != kind {
            increment(&post.reactions, kind: kind)
            post.myReaction = kind
        } else {
            post.myReaction = nil
        }
        socialPosts[idx] = post
        persistSocialPosts()
        if let kind, previous != kind {
            recordEngagementNotification(
                on: postID,
                kind: .systemUpdate,
                actorHandle: currentUserHandle(),
                verb: "reacted (\(kind.shortLabel)) to",
            )
        }
    }

    private func increment(_ tallies: inout CivicReactionTallies, kind: CivicReactionKind) {
        switch kind {
        case .coSign: tallies.willFile += 1
        case .imIn: tallies.needHelp += 1
        case .boost: tallies.disagree += 1
        }
    }

    private func decrement(_ tallies: inout CivicReactionTallies, kind: CivicReactionKind) {
        switch kind {
        case .coSign: tallies.willFile = max(0, tallies.willFile - 1)
        case .imIn: tallies.needHelp = max(0, tallies.needHelp - 1)
        case .boost: tallies.disagree = max(0, tallies.disagree - 1)
        }
    }

    /// Count of co-sign reactions across all posts for a given issue.
    /// Used to surface social proof on Brief / Home cards.
    func willFileCount(for issueID: CivicIssue.ID) -> Int {
        socialPosts
            .filter { $0.issueID == issueID }
            .reduce(0) { $0 + $1.reactions.willFile }
    }

    // MARK: - Comments

    func comments(for postID: SocialPost.ID) -> [CivicComment] {
        visibleComments(for: postID).sorted { $0.createdAt < $1.createdAt }
    }

    func commentCount(for postID: SocialPost.ID) -> Int {
        commentsByPost[postID]?.count ?? 0
    }

    /// Pull-to-refresh on Square: prunes orphaned comments (whose parent
    /// post no longer exists), re-syncs comment counts, and bumps the
    /// social posts collection so the UI animates any state changes.
    func refreshSquare() async {
        let postIDs = Set(socialPosts.map(\.id))
        let orphanedKeys = commentsByPost.keys.filter { !postIDs.contains($0) }
        if !orphanedKeys.isEmpty {
            for key in orphanedKeys { commentsByPost.removeValue(forKey: key) }
            persistComments()
        }
        // Re-sync counts so any external mutation (debug, migration) heals.
        for post in socialPosts {
            let real = commentsByPost[post.id]?.count ?? 0
            if post.commentCount != real {
                if let idx = socialPosts.firstIndex(where: { $0.id == post.id }) {
                    socialPosts[idx].commentCount = real
                }
            }
        }
        persistSocialPosts()
        // Tiny artificial delay so the system pull-to-refresh spinner shows
        // long enough to confirm "yes, I did something".
        try? await Task.sleep(nanoseconds: 250_000_000)
    }

    /// Append a comment from the local user. Returns the saved comment so the
    /// composer can clear or scroll-to-bottom on success.
    @discardableResult
    func addComment(to postID: SocialPost.ID, body: String) -> CivicComment? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let comment = CivicComment(
            postID: postID,
            authorName: "You",
            authorHandle: "@you",
            authorEmoji: "🙂",
            body: trimmed
        )
        commentsByPost[postID, default: []].append(comment)
        syncCommentCount(for: postID)
        persistComments()
        recordEngagementNotification(
            on: postID,
            kind: .systemUpdate,
            actorHandle: comment.authorHandle,
            verb: "commented on",
        )
        Haptics.impact(.light)
        return comment
    }

    func deleteComment(_ commentID: CivicComment.ID, on postID: SocialPost.ID) {
        commentsByPost[postID]?.removeAll { $0.id == commentID }
        syncCommentCount(for: postID)
        persistComments()
    }

    func editComment(_ commentID: CivicComment.ID, on postID: SocialPost.ID, body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard var thread = commentsByPost[postID] else { return }
        guard let idx = thread.firstIndex(where: { $0.id == commentID }) else { return }
        thread[idx].body = trimmed
        commentsByPost[postID] = thread
        persistComments()
    }

    /// Author identity for "is this mine" checks in the UI.
    func isMyComment(_ comment: CivicComment) -> Bool {
        comment.authorHandle == "@you"
    }

    private func syncCommentCount(for postID: SocialPost.ID) {
        guard let idx = socialPosts.firstIndex(where: { $0.id == postID }) else { return }
        socialPosts[idx].commentCount = commentsByPost[postID]?.count ?? 0
        persistSocialPosts()
    }

    private func persistComments() {
        guard let data = try? JSONEncoder().encode(commentsByPost) else { return }
        defaults.set(data, forKey: Self.commentsDefaultsKey)
    }

    // MARK: - Post edit / delete

    func updatePost(_ postID: SocialPost.ID, body: String, kind: SocialPostKind, issueID: CivicIssue.ID?, imageData: Data?) {
        guard let idx = socialPosts.firstIndex(where: { $0.id == postID }) else { return }
        socialPosts[idx].body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        socialPosts[idx].kind = kind
        socialPosts[idx].issueID = issueID
        if let issueID, let issue = issue(with: issueID) {
            socialPosts[idx].issueTitle = issue.title
        } else {
            socialPosts[idx].issueTitle = nil
        }
        socialPosts[idx].imageData = imageData
        persistSocialPosts()
    }

    func deletePost(_ postID: SocialPost.ID) {
        socialPosts.removeAll { $0.id == postID }
        commentsByPost.removeValue(forKey: postID)
        persistSocialPosts()
        persistComments()
    }

    /// Only the local user can edit/delete posts they authored.
    func isMyPost(_ post: SocialPost) -> Bool {
        post.authorHandle == "@you"
    }

    // MARK: - Moderation (Apple Guideline 1.2 — UGC)

    /// Author handles the local user has blocked. Their posts and comments
    /// are filtered from every Square surface until unblocked.
    var blockedAuthors: Set<String> = []

    /// Post IDs the local user has reported. Reported posts are hidden from
    /// their feed pending review. Reports also fire a backend webhook (TBD)
    /// so we can build a moderation queue.
    var reportedPostIDs: Set<SocialPost.ID> = []

    /// Post IDs the user has saved/bookmarked. Surfaces in a "Saved" sheet
    /// + when the user flips the savedOnly filter on Square.
    var savedPostIDs: Set<SocialPost.ID> = []

    /// Thread post IDs the user has muted — silences inbox notifications for
    /// any new comments on these threads.
    var mutedThreadIDs: Set<SocialPost.ID> = []

    func isBlocked(_ handle: String) -> Bool {
        blockedAuthors.contains(handle)
    }

    func isReported(_ postID: SocialPost.ID) -> Bool {
        reportedPostIDs.contains(postID)
    }

    /// User taps "Block this user" on a post. All of that author's content
    /// disappears from their feed immediately. Idempotent.
    func blockAuthor(_ handle: String) {
        guard !handle.isEmpty, handle != "@you" else { return }
        blockedAuthors.insert(handle)
        persistModeration()
    }

    func unblockAuthor(_ handle: String) {
        blockedAuthors.remove(handle)
        persistModeration()
    }

    /// Toggle a post in the saved-posts list. Used by the Square bookmark
    /// button + the "Saved" filter chip.
    @discardableResult
    func toggleSavedPost(_ postID: SocialPost.ID) -> Bool {
        let nowSaved: Bool
        if savedPostIDs.contains(postID) {
            savedPostIDs.remove(postID)
            nowSaved = false
        } else {
            savedPostIDs.insert(postID)
            nowSaved = true
        }
        persistModeration()
        return nowSaved
    }

    func isSaved(_ postID: SocialPost.ID) -> Bool {
        savedPostIDs.contains(postID)
    }

    @discardableResult
    func toggleMuteThread(_ postID: SocialPost.ID) -> Bool {
        let nowMuted: Bool
        if mutedThreadIDs.contains(postID) {
            mutedThreadIDs.remove(postID)
            nowMuted = false
        } else {
            mutedThreadIDs.insert(postID)
            nowMuted = true
        }
        persistModeration()
        return nowMuted
    }

    func isMuted(_ postID: SocialPost.ID) -> Bool {
        mutedThreadIDs.contains(postID)
    }

    /// Set / change / clear RSVP on a `.event` post. Tallies are bumped/decremented.
    func setRSVP(_ kind: EventRSVPKind?, on postID: SocialPost.ID) {
        guard let idx = socialPosts.firstIndex(where: { $0.id == postID }) else { return }
        var post = socialPosts[idx]
        guard post.kind == .event else { return }
        let prior = post.myRsvp
        if let prior {
            switch prior {
            case .going: post.eventRSVPs.going = max(0, post.eventRSVPs.going - 1)
            case .interested: post.eventRSVPs.interested = max(0, post.eventRSVPs.interested - 1)
            case .cantGo: post.eventRSVPs.cantGo = max(0, post.eventRSVPs.cantGo - 1)
            }
        }
        if let kind, kind != prior {
            switch kind {
            case .going: post.eventRSVPs.going += 1
            case .interested: post.eventRSVPs.interested += 1
            case .cantGo: post.eventRSVPs.cantGo += 1
            }
            post.myRsvp = kind
        } else {
            post.myRsvp = nil
        }
        socialPosts[idx] = post
        persistSocialPosts()
    }

    /// Record a vote on a `.poll` post. Idempotent — switching votes reassigns
    /// without double-counting; voting the same option again is a no-op.
    func voteOnPoll(_ optionID: UUID, on postID: SocialPost.ID) {
        guard let idx = socialPosts.firstIndex(where: { $0.id == postID }) else { return }
        var post = socialPosts[idx]
        guard post.kind == .poll, var options = post.pollOptions else { return }
        if let prior = post.myPollVote {
            if prior == optionID { return }
            if let pIdx = options.firstIndex(where: { $0.id == prior }) {
                options[pIdx].voteCount = max(0, options[pIdx].voteCount - 1)
            }
        }
        if let nIdx = options.firstIndex(where: { $0.id == optionID }) {
            options[nIdx].voteCount += 1
        }
        post.pollOptions = options
        post.myPollVote = optionID
        socialPosts[idx] = post
        persistSocialPosts()
    }

    /// Toggle pinned state — appears at top of City scope. Currently exposed
    /// via long-press on your own post. Future: moderator-only pin for
    /// city-government accounts.
    func togglePinned(_ postID: SocialPost.ID) {
        guard let idx = socialPosts.firstIndex(where: { $0.id == postID }) else { return }
        socialPosts[idx].isPinned.toggle()
        persistSocialPosts()
    }

    /// Create a repost — a new SocialPost that references the original via
    /// `repostOfID` and carries the local user's commentary as its body.
    @discardableResult
    func repostPost(_ originalID: SocialPost.ID, commentary: String) -> SocialPost? {
        guard let original = socialPosts.first(where: { $0.id == originalID }) else { return nil }
        let post = SocialPost(
            authorName: currentUserDisplayName(),
            authorHandle: currentUserHandle(),
            authorEmoji: "🗣️",
            body: commentary,
            kind: .discussion,
            issueID: original.issueID,
            issueTitle: original.issueTitle,
            locality: profile?.localityLabel ?? original.locality,
            createdAt: .now,
            repostOfID: originalID,
        )
        socialPosts.insert(post, at: 0)
        persistSocialPosts()
        return post
    }

    /// Convenience accessor used by repost + RSVP/poll lookup. Mirrors the
    /// handle assigned in `createSocialPost`.
    func currentUserHandle() -> String { "@you" }

    func currentUserDisplayName() -> String { "You" }

    func post(withID id: SocialPost.ID) -> SocialPost? {
        socialPosts.first { $0.id == id }
    }

    /// Drop an inbox notification for the post author when someone else
    /// engages — caller passes the actor handle so we can skip self-engagement.
    /// No-op when the post author isn't the current user (i.e. someone else's
    /// post) or when the thread is muted.
    func recordEngagementNotification(
        on postID: SocialPost.ID,
        kind: AthenInboxNotification.Kind,
        actorHandle: String,
        verb: String,
    ) {
        guard let post = post(withID: postID) else { return }
        guard post.authorHandle == currentUserHandle() else { return }
        guard actorHandle != currentUserHandle() else { return }
        guard !mutedThreadIDs.contains(postID) else { return }
        let trimmed = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = trimmed.isEmpty ? (post.issueTitle ?? "your post") : String(trimmed.prefix(60))
        recordInboxNotification(
            .init(
                id: "inbox.engagement.\(postID.uuidString).\(actorHandle).\(verb)",
                kind: kind,
                title: "\(actorHandle) \(verb) your post",
                body: preview,
                issueID: post.issueID,
                scheduledAtISO: ISO8601DateFormatter().string(from: .now),
                isRead: false,
            ),
        )
    }

    /// User taps "Report" on a post. Hides locally immediately and fires a
    /// fire-and-forget POST to /v1/moderation/report. The post is surfaced
    /// in a human review queue with a 24-hour SLA per Apple Guideline 1.2.
    func reportPost(_ postID: SocialPost.ID, reason: String) {
        reportedPostIDs.insert(postID)
        persistModeration()
        let service = moderationService
        let id = postID.uuidString
        Task {
            // Fire-and-forget; the local hide is what the user sees. A backend
            // failure here doesn't unwind that — the report is queued in
            // UserDefaults via reportedPostIDs and a v1.1 retry path can flush.
            _ = try? await service.reportPost(postId: id, reason: reason)
        }
    }

    /// Same contract as reportPost but for an individual comment. We share
    /// the moderation endpoint — the backend distinguishes by ID format and
    /// queues both for the same human review process.
    func reportComment(_ comment: CivicComment, reason: String) {
        let service = moderationService
        let id = comment.id.uuidString
        Task {
            _ = try? await service.reportPost(postId: "comment:\(id)", reason: reason)
        }
    }

    /// Post visibility for the feed — blocked authors + self-reported posts
    /// are filtered. Applied centrally so every Square surface stays in sync.
    var visibleSocialPosts: [SocialPost] {
        socialPosts.filter { post in
            !blockedAuthors.contains(post.authorHandle) && !reportedPostIDs.contains(post.id)
        }
    }

    func visibleComments(for postID: SocialPost.ID) -> [CivicComment] {
        let raw = commentsByPost[postID] ?? []
        return raw.filter { !blockedAuthors.contains($0.authorHandle) }
    }

    private static let blockedAuthorsKey = "athen.moderation.blocked-authors.v1"
    private static let reportedPostsKey = "athen.moderation.reported-posts.v1"
    private static let savedPostsKey = "athen.saved-posts.v1"
    private static let mutedThreadsKey = "athen.muted-threads.v1"

    private func persistModeration() {
        if let data = try? JSONEncoder().encode(Array(blockedAuthors)) {
            defaults.set(data, forKey: Self.blockedAuthorsKey)
        }
        if let data = try? JSONEncoder().encode(Array(reportedPostIDs)) {
            defaults.set(data, forKey: Self.reportedPostsKey)
        }
        if let data = try? JSONEncoder().encode(Array(savedPostIDs)) {
            defaults.set(data, forKey: Self.savedPostsKey)
        }
        if let data = try? JSONEncoder().encode(Array(mutedThreadIDs)) {
            defaults.set(data, forKey: Self.mutedThreadsKey)
        }
    }

    /// Called once during init to rehydrate moderation state from UserDefaults.
    fileprivate func loadModerationFromDefaults() {
        if let data = defaults.data(forKey: Self.blockedAuthorsKey),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            blockedAuthors = Set(saved)
        }
        if let data = defaults.data(forKey: Self.reportedPostsKey),
           let saved = try? JSONDecoder().decode([SocialPost.ID].self, from: data) {
            reportedPostIDs = Set(saved)
        }
        if let data = defaults.data(forKey: Self.savedPostsKey),
           let saved = try? JSONDecoder().decode([SocialPost.ID].self, from: data) {
            savedPostIDs = Set(saved)
        }
        if let data = defaults.data(forKey: Self.mutedThreadsKey),
           let saved = try? JSONDecoder().decode([SocialPost.ID].self, from: data) {
            mutedThreadIDs = Set(saved)
        }
    }

    func logShare(on postID: SocialPost.ID) {
        guard let idx = socialPosts.firstIndex(where: { $0.id == postID }) else { return }
        socialPosts[idx].shareCount += 1
        persistSocialPosts()
    }

    func queueSocialComposer(for issue: CivicIssue) {
        pendingSocialIssueID = issue.id
    }

    func consumePendingSocialIssueID() -> CivicIssue.ID? {
        let id = pendingSocialIssueID
        pendingSocialIssueID = nil
        return id
    }

    private func defaultSocialCaption(kind: SocialPostKind, issue: CivicIssue?) -> String {
        let issueName = issue?.title ?? "a civic item"
        switch kind {
        case .discussion:
            return "What do folks think about \(issueName)?"
        case .aiBrief:
            return "Here is the plain-English brief on \(issueName)."
        case .filed:
            return "I filed on \(issueName)."
        case .rally:
            return "Rallying people around \(issueName)."
        case .event:
            return "Heads-up — there's something happening around \(issueName)."
        case .poll:
            return "Quick poll on \(issueName)."
        case .explainer:
            return "Here is the plain-English version of \(issueName)."
        case .question:
            return "I have a question about \(issueName)."
        }
    }

    private func persistSocialPosts() {
        guard let data = try? JSONEncoder().encode(socialPosts) else { return }
        defaults.set(data, forKey: Self.socialPostsDefaultsKey)
    }

    func refreshAthenBriefs() async {
        guard !isRefreshingAthenBriefs else { return }
        isRefreshingAthenBriefs = true
        lastAthenBriefRefreshError = nil
        defer { isRefreshingAthenBriefs = false }

        do {
            let posts = try await athenBriefService.fetchBriefPosts(for: profile)
            guard !posts.isEmpty else { return }
            let backendIssueIDs = Set(posts.compactMap(\.issueID))
            socialPosts.removeAll { post in
                post.authorHandle == "@athen.brief" &&
                    post.kind == .aiBrief &&
                    post.issueID.map { backendIssueIDs.contains($0) } == true
            }
            socialPosts.insert(contentsOf: posts, at: 0)
            persistSocialPosts()
        } catch {
            lastAthenBriefRefreshError = (error as? LocalizedError)?.errorDescription ?? "Could not load Athen briefs."
        }
    }

    // MARK: - Services and resident help

    var prioritizedServices: [CivicService] {
        services.sorted { lhs, rhs in
            let lhsScore = lhs.matchScore(for: profile)
            let rhsScore = rhs.matchScore(for: profile)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.category.label < rhs.category.label
        }
    }

    var serviceReadiness: Int {
        guard let profile else { return 0 }
        var score = 0
        if !profile.serviceNeeds.isEmpty { score += 25 }
        if !profile.eligibilitySignals.isEmpty { score += 25 }
        if profile.householdSize != .unknown { score += 15 }
        if profile.incomeBand != .unknown { score += 15 }
        if profile.preferredLanguage != .english { score += 5 }
        score += min(profile.preparedDocuments.count * 3, 15)
        return min(score, 100)
    }

    var matchedServices: [CivicService] {
        let top = prioritizedServices.filter { $0.matchScore(for: profile) >= 45 }
        return top.isEmpty ? Array(prioritizedServices.prefix(4)) : top
    }

    func setServiceNeeds(_ needs: Set<ServiceCategory>) {
        guard var current = profile else { return }
        current.serviceNeeds = needs
        profile = current
        persist(current)
    }

    func setEligibilitySignals(_ signals: Set<EligibilitySignal>) {
        guard var current = profile else { return }
        current.eligibilitySignals = signals
        profile = current
        persist(current)
    }

    func setHouseholdSize(_ size: HouseholdSize) {
        guard var current = profile else { return }
        current.householdSize = size
        profile = current
        persist(current)
    }

    func setIncomeBand(_ band: IncomeBand) {
        guard var current = profile else { return }
        current.incomeBand = band
        profile = current
        persist(current)
    }

    func setPreferredLanguage(_ language: ResidentLanguage) {
        guard var current = profile else { return }
        current.preferredLanguage = language
        profile = current
        persist(current)
    }

    func togglePreparedDocument(_ document: CivicDocumentKind) {
        guard var current = profile else { return }
        if current.preparedDocuments.contains(document) {
            current.preparedDocuments.remove(document)
        } else {
            current.preparedDocuments.insert(document)
        }
        profile = current
        persist(current)
    }

    // MARK: - Bookmarks

    func toggleBookmark(_ issue: CivicIssue) {
        let wasBookmarked = bookmarkedIssueIDs.contains(issue.id)
        if wasBookmarked {
            bookmarkedIssueIDs.remove(issue.id)
            bookmarkSnapshots.removeValue(forKey: issue.id)
            persistBookmarkSnapshots()
        } else {
            bookmarkedIssueIDs.insert(issue.id)
            // Capture the current state as the baseline so future changes
            // can be diffed against it.
            bookmarkSnapshots[issue.id] = BookmarkSnapshot(from: issue)
            persistBookmarkSnapshots()
            // Fire the Composio calendar-event automation on new bookmarks.
            // No-op when the toggle is off or Google Calendar isn't connected.
            onBookmarkAdded(issue)
        }
        persistBookmarks()
        Task { await rescheduleNotifications() }
    }

    // MARK: - Diff watcher

    /// Walk every bookmarked issue, compare its current state to the stored
    /// snapshot, and emit a `CivicDiffEvent` for any meaningful change.
    /// Called automatically after every issue refresh.
    func detectBookmarkDiffs() {
        var newEvents: [CivicDiffEvent] = []
        for issue in issues where bookmarkedIssueIDs.contains(issue.id) {
            guard let snap = bookmarkSnapshots[issue.id] else {
                // First time seeing this bookmarked issue post-bookmark —
                // just capture a baseline. No diff yet.
                bookmarkSnapshots[issue.id] = BookmarkSnapshot(from: issue)
                continue
            }
            // Title changed?
            if snap.title != issue.title {
                newEvents.append(CivicDiffEvent(
                    issueID: issue.id,
                    issueTitle: issue.title,
                    kind: .titleChanged,
                    oldValue: snap.title,
                    newValue: issue.title
                ))
            }
            // Summary changed?
            if snap.summary != issue.summary && !issue.summary.isEmpty {
                newEvents.append(CivicDiffEvent(
                    issueID: issue.id,
                    issueTitle: issue.title,
                    kind: .summaryChanged,
                    oldValue: snap.summary,
                    newValue: issue.summary
                ))
            }
            // Vote date changed?
            let freshVoteISO = ISO8601DateFormatter().string(from: issue.voteDate)
            if snap.voteDateISO != freshVoteISO {
                newEvents.append(CivicDiffEvent(
                    issueID: issue.id,
                    issueTitle: issue.title,
                    kind: .voteDateChanged,
                    oldValue: snap.voteDateISO,
                    newValue: freshVoteISO
                ))
            }
            // Update the snapshot regardless.
            bookmarkSnapshots[issue.id] = BookmarkSnapshot(from: issue)
        }
        if !newEvents.isEmpty {
            diffEvents.insert(contentsOf: newEvents, at: 0)
            // Cap at the last 50 events to keep storage sane.
            if diffEvents.count > 50 { diffEvents = Array(diffEvents.prefix(50)) }
            persistDiffEvents()
            persistBookmarkSnapshots()
            Haptics.impact(.light)
        }
    }

    func acknowledgeDiff(_ id: CivicDiffEvent.ID) {
        diffEvents.removeAll { $0.id == id }
        persistDiffEvents()
    }

    func clearAllDiffs() {
        diffEvents.removeAll()
        persistDiffEvents()
    }

    private func persistBookmarkSnapshots() {
        guard let data = try? JSONEncoder().encode(bookmarkSnapshots) else { return }
        defaults.set(data, forKey: Self.bookmarkSnapshotsKey)
    }

    private func persistDiffEvents() {
        guard let data = try? JSONEncoder().encode(diffEvents) else { return }
        defaults.set(data, forKey: Self.diffEventsKey)
    }

    // MARK: - Civic streak

    /// Call once on every app foreground. Bumps the streak if today is a new
    /// calendar day; resets to 1 if more than a day has passed.
    func touchStreak(now: Date = .now) {
        previousLastOpenedAt = lastOpenedAt
        lastOpenedAt = now
        defaults.set(now, forKey: Self.lastOpenedAtKey)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let today = formatter.string(from: now)

        if let last = lastOpenedDay {
            if last == today { return }
            let yesterday = formatter.string(from: now.addingTimeInterval(-86400))
            if last == yesterday {
                civicStreakDays += 1
            } else {
                civicStreakDays = 1
            }
        } else {
            civicStreakDays = 1
        }
        lastOpenedDay = today
        persistStreak()
    }

    private func persistStreak() {
        let snap = StreakSnapshot(days: civicStreakDays, lastOpenedDay: lastOpenedDay)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        defaults.set(data, forKey: Self.streakKey)
    }

    private struct StreakSnapshot: Codable {
        let days: Int
        let lastOpenedDay: String?
    }

    // MARK: - Undo Send

    /// Replaces direct `confirmSend` for UX with an undo window. Returns a
    /// handle the toast view uses to either cancel or commit the send.
    @discardableResult
    func queueSend(_ draft: DraftedFiling, undoWindowSeconds: Double = 5) -> PendingSendHandle {
        let handle = PendingSendHandle(
            issueID: draft.issue.id,
            issueTitle: draft.issue.title,
            draft: draft,
            expiresAt: .now.addingTimeInterval(undoWindowSeconds)
        )
        pendingSends[draft.issue.id] = handle
        // Mark filing status as "sending" so UI reflects the pending state.
        filingStatuses[draft.issue.id] = .sending(draft.action)
        Task { [handle] in
            try? await Task.sleep(nanoseconds: UInt64(undoWindowSeconds * 1_000_000_000))
            // If still pending after the window, actually fire the send.
            if pendingSends[handle.issueID] != nil {
                pendingSends.removeValue(forKey: handle.issueID)
                await confirmSend(handle.draft)
            }
        }
        return handle
    }

    /// Cancel a queued send while the undo window is still open.
    func cancelPendingSend(_ issueID: CivicIssue.ID) {
        guard pendingSends[issueID] != nil else { return }
        pendingSends.removeValue(forKey: issueID)
        filingStatuses[issueID] = .ready
        Haptics.impact(.light)
    }

    func isBookmarked(_ issue: CivicIssue) -> Bool {
        bookmarkedIssueIDs.contains(issue.id)
    }

    var bookmarkedIssues: [CivicIssue] {
        issues.filter { bookmarkedIssueIDs.contains($0.id) }
    }

    private func persistBookmarks() {
        let array = Array(bookmarkedIssueIDs)
        guard let data = try? JSONEncoder().encode(array) else { return }
        defaults.set(data, forKey: Self.bookmarksDefaultsKey)
    }

    // MARK: - Filing history (derived)

    struct FilingHistoryEntry: Identifiable, Equatable, Hashable {
        let issue: CivicIssue
        let receipt: FilingReceipt

        var id: CivicIssue.ID { issue.id }
    }

    var filingHistory: [FilingHistoryEntry] {
        filingStatuses.compactMap { entry -> FilingHistoryEntry? in
            guard let receipt = entry.value.receipt,
                  let issue = issues.first(where: { $0.id == entry.key })
            else { return nil }
            return FilingHistoryEntry(issue: issue, receipt: receipt)
        }
        .sorted { $0.receipt.sentAt > $1.receipt.sentAt }
    }

    // MARK: - Background reading

    func loadBackgroundIfNeeded(for issue: CivicIssue) {
        guard backgroundByIssue[issue.id] == nil,
              !loadingBackgroundFor.contains(issue.id) else { return }
        loadingBackgroundFor.insert(issue.id)
        let svc = newsService
        let state = profile?.stateCode
        Task { [weak self] in
            do {
                let reading = try await svc.background(for: issue, stateCode: state)
                await MainActor.run {
                    guard let self else { return }
                    self.loadingBackgroundFor.remove(issue.id)
                    if let reading {
                        self.backgroundByIssue[issue.id] = reading
                    }
                }
            } catch {
                await MainActor.run {
                    _ = self?.loadingBackgroundFor.remove(issue.id)
                }
            }
        }
    }

    // MARK: - Deep links

    /// Handle an app deep link. Stores the target issue id so the
    /// active tab can pick it up and push the detail view.
    func handleDeepLink(_ url: URL) -> Bool {
        guard url.scheme == "athen" || url.scheme == "civicos" else { return false }
        if url.host == "feed" {
            pendingFeedOpen = true
            return true
        }
        if url.host == "help" {
            pendingHelpOpen = true
            return true
        }
        if url.host == "issue" {
            let raw = url.pathComponents.dropFirst().first ?? ""
            if let id = UUID(uuidString: raw), issues.contains(where: { $0.id == id }) {
                pendingDeepLinkIssueID = id
                return true
            }
        }
        return false
    }

    func consumePendingFeedOpen() -> Bool {
        let shouldOpen = pendingFeedOpen
        pendingFeedOpen = false
        return shouldOpen
    }

    func consumePendingHelpOpen() -> Bool {
        let shouldOpen = pendingHelpOpen
        pendingHelpOpen = false
        return shouldOpen
    }

    func consumePendingDeepLink() -> CivicIssue.ID? {
        let id = pendingDeepLinkIssueID
        pendingDeepLinkIssueID = nil
        return id
    }

    // MARK: - Settings

    func completeOnboarding() {
        guard !settings.hasCompletedOnboarding else { return }
        settings.hasCompletedOnboarding = true
        persistSettings()
    }

    func setShowSampleIssues(_ enabled: Bool) {
        settings.showSampleIssues = enabled
        persistSettings()
        if enabled {
            // Merge samples in; preserve any live issues already loaded.
            let liveIDs = Set(issues.map(\.id))
            let extras = MockCivicData.allIssues.filter { !liveIDs.contains($0.id) }
            issues.append(contentsOf: extras)
        } else {
            // Strip samples; keep only live issues.
            let sampleIDs = Set(MockCivicData.allIssues.map(\.id))
            issues.removeAll { sampleIDs.contains($0.id) }
        }
    }

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.settingsDefaultsKey)
    }

    private func persistFilingStatuses() {
        let receiptsOnly: [CivicIssue.ID: FilingReceipt] = filingStatuses.reduce(into: [:]) { acc, entry in
            if case let .sent(receipt) = entry.value {
                acc[entry.key] = receipt
            }
        }
        guard let data = try? JSONEncoder().encode(receiptsOnly) else { return }
        defaults.set(data, forKey: Self.filingStatusesDefaultsKey)
    }

    // MARK: - Backend wiring

    /// Currently active backend base URL (settings override → ProcessInfo env → nil for mocks).
    var effectiveBackendURL: URL? {
        if let raw = settings.backendURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw)
        {
            return url
        }
        return Self.configuredBaseURL()
    }

    /// Persist a new backend URL (or clear it) and rebuild all HTTP services in
    /// place so the next request lands on the new host. A nil/empty input
    /// reverts to mocks (or the `CIVIC_API_BASE_URL` env var if present).
    func setBackendURL(_ raw: String?) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.backendURL = trimmed?.isEmpty == true ? nil : trimmed
        persistSettings()
        rebuildServices()
        backendStatus = .unknown
        sourcesSnapshot = nil
        scheduleAutoRefresh()
    }

    private func userFacingErrorMessage(_ error: Error, fallback: String) -> String {
        if let message = (error as? LocalizedError)?.errorDescription,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        let localized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return localized.isEmpty ? fallback : localized
    }

    private func isConnectivityError(_ error: Error) -> Bool {
        if error is URLError { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return true }
        if let filingError = error as? CivicFilingError {
            switch filingError {
            case .server(let status, _):
                return status == 0
            case .invalidResponse:
                return false
            }
        }
        return false
    }

    private func markBackendOfflineIfNeeded(_ error: Error, baseURL: URL?) {
        guard let baseURL, isConnectivityError(error) else { return }
        backendStatus = .offline(
            message: userFacingErrorMessage(error, fallback: "Could not reach the backend."),
            baseURL: baseURL.absoluteString
        )
    }

    private func rebuildServices() {
        if let url = effectiveBackendURL {
            filingService = HTTPCivicFilingService(
                baseURL: url,
                gmailEntityID: integrationEntityID,
                useUserGmail: isGmailFilingEnabled && isGmailConnected
            )
            profileResolver = HTTPProfileResolverService(baseURL: url)
            chatService = HTTPChatService(baseURL: url)
            newsService = HTTPNewsService(baseURL: url)
            issueService = HTTPIssueService(baseURL: url)
            athenBriefService = HTTPAthenBriefService(baseURL: url)
            voiceService = HTTPVoiceService(baseURL: url)
            sourcesService = HTTPSourcesService(baseURL: url)
            refreshService = HTTPRefreshService(baseURL: url)
            briefService = HTTPBriefService(baseURL: url)
            draftVariantsService = HTTPDraftVariantsService(baseURL: url)
            ballotService = HTTPBallotService(baseURL: url)
            integrationsService = HTTPIntegrationsService(baseURL: url)
            petitionsService = HTTPPetitionsService(baseURL: url)
            voterRailService = HTTPVoterRailService(baseURL: url)
            lifeEventsService = HTTPLifeEventsService(baseURL: url)
            directoryService = HTTPOfficialsDirectoryService(baseURL: url)
            speechService = HTTPSpeechService(baseURL: url)
            moderationService = HTTPModerationService(baseURL: url)
            savedSearchService = HTTPSavedSearchService(baseURL: url)
            timelineService = HTTPTimelineService(baseURL: url)
            urlAnalyzeService = HTTPUrlAnalyzeService(baseURL: url)
            personalImpactService = HTTPPersonalImpactService(baseURL: url)
        } else {
            filingService = MockCivicFilingService()
            profileResolver = MockProfileResolverService()
            chatService = MockChatService()
            newsService = MockNewsService()
            issueService = MockIssueService()
            athenBriefService = MockAthenBriefService()
            voiceService = MockVoiceService()
            sourcesService = MockSourcesService()
            refreshService = MockRefreshService()
            briefService = MockBriefService()
            draftVariantsService = MockDraftVariantsService()
            ballotService = MockBallotService()
            integrationsService = MockIntegrationsService()
            petitionsService = MockPetitionsService()
            voterRailService = MockVoterRailService()
            lifeEventsService = MockLifeEventsService()
            directoryService = MockOfficialsDirectoryService()
            speechService = MockSpeechService()
            moderationService = MockModerationService()
            savedSearchService = MockSavedSearchService()
            timelineService = MockTimelineService()
            urlAnalyzeService = MockUrlAnalyzeService()
            personalImpactService = MockPersonalImpactService()
        }
    }

    // MARK: - Orchestrator (full refresh)

    /// Outcome of a full-refresh attempt. The toast/UI uses this instead of
    /// trying to diff `lastRefreshReport` (which could be stale from a prior
    /// run that early-returned).
    enum RefreshOutcome: Equatable {
        /// Refresh completed end-to-end. Caller can read `lastRefreshReport`
        /// for the per-source breakdown.
        case ran(inserted: Int, updated: Int)
        /// Skipped because another refresh was already in flight.
        case alreadyRunning
        /// Skipped because the last refresh completed less than `minimumAge`
        /// seconds ago. Used by silent auto-refresh.
        case skippedRecent(secondsAgo: Int)
        /// Orchestrator endpoint failed but we still pulled what we could.
        case failed(reason: String)
        /// Local-mode fallback (no backend URL configured) — refreshed mocks.
        case mockMode
    }

    /// Timestamp of the last successful run. Drives the stale-badge on the
    /// refresh button + the smart "refresh on foreground" cooldown.
    var lastRefreshCompletedAt: Date?

    /// Runs the backend orchestrator (Legistar + OpenStates + Federal Register
    /// in parallel) then pulls fresh issues + sources. This is what the Home
    /// refresh button calls — gives the user real new items instead of a no-op.
    @discardableResult
    func runFullRefresh(minimumAge: TimeInterval = 0) async -> RefreshOutcome {
        if minimumAge > 0, let last = lastRefreshCompletedAt {
            let age = Date.now.timeIntervalSince(last)
            if age < minimumAge {
                return .skippedRecent(secondsAgo: Int(age))
            }
        }
        guard !isRunningOrchestrator else { return .alreadyRunning }
        isRunningOrchestrator = true
        lastOrchestratorError = nil
        defer { isRunningOrchestrator = false }

        let backendURL = effectiveBackendURL
        if backendURL == nil {
            // Mocks have nothing to orchestrate — fall back to the local refresh.
            await refreshIssues()
            await refreshSources()
            lastRefreshCompletedAt = .now
            backendStatus = .mockMode
            return .mockMode
        }

        var failureReason: String?
        do {
            lastRefreshReport = try await refreshService.triggerRefresh()
        } catch {
            let msg = userFacingErrorMessage(error, fallback: "Refresh failed.")
            lastOrchestratorError = msg
            failureReason = msg
            markBackendOfflineIfNeeded(error, baseURL: backendURL)
            // Even if orchestrator fails, try to pull what we have.
        }
        async let issuesLoaded = refreshIssues()
        async let sourcesLoaded = refreshSources()
        let loaded = await (issuesLoaded, sourcesLoaded)
        if failureReason == nil || loaded.0 || loaded.1 {
            lastRefreshCompletedAt = .now
        }

        if let failureReason {
            return .failed(reason: failureReason)
        }
        let report = lastRefreshReport
        return .ran(
            inserted: report?.totalInserted ?? 0,
            updated: report?.totalUpdated ?? 0,
        )
    }

    /// True when the user is overdue for fresh data — feed should remind them
    /// via a small dot on the refresh button.
    var isFeedStale: Bool {
        guard let last = lastRefreshCompletedAt else { return true }
        return Date.now.timeIntervalSince(last) > 6 * 3600
    }

    // MARK: - Brief (AI explanations)

    /// Load the digest of top issues + their Claude-generated briefs.
    ///
    /// Two-phase by default:
    ///   1. Fast pull (`warm=false`) — returns cached briefs immediately so
    ///      the Brief tab paints in <1s.
    ///   2. Background warm-up (`warm=true`) — generates any missing briefs
    ///      in parallel on the backend, then replaces the digest in place.
    ///
    /// The UI shows a "Thinking…" spinner only during phase 2.
    func loadBriefDigest(warm: Bool = false) async {
        guard !isLoadingBriefDigest else { return }
        isLoadingBriefDigest = true
        lastBriefError = nil

        // Phase 1: instant paint of whatever's already cached.
        do {
            let cached = try await briefService.fetchDigest(
                stateCode: profile?.stateCode,
                zip: profile?.zipCode,
                limit: 8,
                warm: false
            )
            briefDigest = cached
            for item in cached.items {
                if let brief = item.brief {
                    briefAnalyses[item.issueId] = brief
                }
            }
        } catch {
            lastBriefError = (error as? LocalizedError)?.errorDescription ?? "Could not load briefs."
        }

        // Phase 2: warm up any missing briefs. Only run if requested AND there
        // are items without briefs yet, otherwise it's just wasted Claude cost.
        let needsWarm = warm && (briefDigest?.items.contains(where: { $0.brief == nil }) ?? true)
        guard needsWarm else {
            isLoadingBriefDigest = false
            return
        }

        do {
            let warmed = try await briefService.fetchDigest(
                stateCode: profile?.stateCode,
                zip: profile?.zipCode,
                limit: 8,
                warm: true
            )
            briefDigest = warmed
            for item in warmed.items {
                if let brief = item.brief {
                    briefAnalyses[item.issueId] = brief
                }
            }
        } catch {
            lastBriefError = (error as? LocalizedError)?.errorDescription ?? "Brief warm-up failed."
        }
        isLoadingBriefDigest = false
    }

    /// Force-regenerate every Claude brief — bypasses the cache so every
    /// visible item gets a fresh analysis with the current prompt + date
    /// context. Used by the "Regenerate all" menu action.
    func forceRegenerateAllBriefs() async {
        guard !isLoadingBriefDigest else { return }
        isLoadingBriefDigest = true
        lastBriefError = nil

        let items = briefDigest?.items ?? []
        var freshAnalyses: [String: CivicBriefAnalysis] = [:]
        var failures = 0
        // Bound parallelism so we don't fan out 8 simultaneous Claude calls.
        await withTaskGroup(of: (String, Result<CivicBriefAnalysis, Error>).self) { group in
            for item in items {
                group.addTask { [briefService = self.briefService] in
                    do {
                        let brief = try await briefService.fetchBrief(issueId: item.issueId, force: true)
                        return (item.issueId, .success(brief))
                    } catch {
                        return (item.issueId, .failure(error))
                    }
                }
            }
            for await (issueId, result) in group {
                switch result {
                case .success(let brief): freshAnalyses[issueId] = brief
                case .failure: failures += 1
                }
            }
        }
        for (id, brief) in freshAnalyses {
            briefAnalyses[id] = brief
        }
        // Reflect regenerated briefs back into the digest in place so cards
        // re-render without another network round-trip.
        if let digest = briefDigest {
            let updatedItems = digest.items.map { item -> CivicBriefDigestItem in
                guard let brief = freshAnalyses[item.issueId] else { return item }
                return CivicBriefDigestItem(issueId: item.issueId, issue: item.issue, brief: brief)
            }
            briefDigest = CivicBriefDigest(
                generatedAt: .now,
                items: updatedItems,
                cacheStats: digest.cacheStats
            )
        }
        if failures > 0 {
            lastBriefError = failures == items.count
                ? "Couldn't regenerate any briefs. Check backend."
                : "\(failures) of \(items.count) briefs failed to regenerate."
        }
        // Release the guard BEFORE calling loadBriefDigest, otherwise its own
        // guard early-returns and the digest never syncs with the cache.
        isLoadingBriefDigest = false
    }

    /// What the Brief tab's "Pull fresh briefs" menu action calls: pulls
    /// fresh civic items from upstream APIs (Legistar / OpenStates / Federal
    /// Register) AND warms briefs for anything new. Always does something
    /// visible — the orchestrator either adds new items or refreshes their
    /// timestamps.
    func refreshBriefFeed() async {
        guard !isLoadingBriefDigest, !isRunningOrchestrator else { return }
        lastBriefError = nil
        await runFullRefresh()
        // After the orchestrator settles, the issue store may have new items.
        // Reload digest with warm=true to generate briefs for them.
        await loadBriefDigest(warm: true)
    }

    /// Re-pulls the brief digest after the user triggers a civic-data refresh
    /// from the Brief tab so they see fresh items without a second tap.
    func refreshCivicDataFromBriefTab() async {
        guard !isRunningOrchestrator else { return }
        await runFullRefresh()
        await loadBriefDigest(warm: false)
    }

    /// Force-generate a brief for a specific issue (used by tap-to-deepen).
    func generateBrief(for issueId: String) async {
        guard !generatingBriefFor.contains(issueId) else { return }
        generatingBriefFor.insert(issueId)
        defer { generatingBriefFor.remove(issueId) }
        do {
            let brief = try await briefService.fetchBrief(issueId: issueId)
            briefAnalyses[issueId] = brief
            // Reflect back into the digest so the card updates in-place.
            if var digest = briefDigest {
                if let idx = digest.items.firstIndex(where: { $0.issueId == issueId }) {
                    let existing = digest.items[idx]
                    let updatedItem = CivicBriefDigestItem(
                        issueId: existing.issueId,
                        issue: existing.issue,
                        brief: brief
                    )
                    var items = digest.items
                    items[idx] = updatedItem
                    briefDigest = CivicBriefDigest(
                        generatedAt: digest.generatedAt,
                        items: items,
                        cacheStats: digest.cacheStats
                    )
                }
            }
        } catch {
            lastBriefError = (error as? LocalizedError)?.errorDescription ?? "Brief generation failed."
        }
    }

    func brief(for issueId: String) -> CivicBriefAnalysis? {
        briefAnalyses[issueId]
    }

    /// Claude-rewrite of the existing brief targeted at one audience.
    /// One-shot; the caller owns presentation + caching.
    func rewriteBrief(for issueId: String, audience: BriefAudience) async throws -> String {
        try await briefService.rewriteBrief(issueId: issueId, audience: audience)
    }

    // MARK: - Audio briefing

    func loadAudioBriefing() async {
        guard !isGeneratingAudioBriefing else { return }
        isGeneratingAudioBriefing = true
        lastAudioBriefingError = nil
        defer { isGeneratingAudioBriefing = false }
        do {
            let focus = audioBriefingFocus.trimmingCharacters(in: .whitespacesAndNewlines)
            audioBriefing = try await briefService.fetchAudioBriefing(
                stateCode: profile?.stateCode,
                stateName: profile?.stateName,
                zip: profile?.zipCode,
                duration: audioBriefingDurationMin,
                voiceId: audioBriefingVoiceId,
                focus: focus.isEmpty ? nil : focus
            )
        } catch {
            lastAudioBriefingError = (error as? LocalizedError)?.errorDescription ?? "Audio briefing failed."
        }
    }

    /// Wipe the cached briefing + player state so the next play triggers
    /// a fresh render with the current customization settings. Use after
    /// the user changes duration / voice / focus.
    func resetAudioBriefingForRegeneration() {
        AudioBriefingPlayer.shared.stop()
        audioBriefing = nil
        lastAudioBriefingError = nil
    }

    // MARK: - Sources

    @discardableResult
    func refreshSources() async -> Bool {
        guard !isRefreshingSources else { return false }
        isRefreshingSources = true
        lastSourcesError = nil
        defer { isRefreshingSources = false }
        do {
            let snapshot = try await sourcesService.fetchSources()
            sourcesSnapshot = snapshot
            // Prune any disabled IDs that no longer exist in the registry —
            // keeps the persisted set from growing stale across deploys.
            let validIDs = Set(snapshot.sources.map(\.id))
            if !settings.disabledSourceIDs.isSubset(of: validIDs) {
                settings.disabledSourceIDs.formIntersection(validIDs)
                persistSettings()
            }
            return true
        } catch {
            let message = userFacingErrorMessage(error, fallback: "Could not load sources.")
            lastSourcesError = message
            markBackendOfflineIfNeeded(error, baseURL: effectiveBackendURL)
            return false
        }
    }

    var allSources: [CivicSourceDescriptor] {
        sourcesSnapshot?.sources ?? []
    }

    var enabledSources: [CivicSourceDescriptor] {
        allSources.filter { !settings.disabledSourceIDs.contains($0.id) }
    }

    func isSourceEnabled(_ id: String) -> Bool {
        !settings.disabledSourceIDs.contains(id)
    }

    func setSourceEnabled(_ id: String, enabled: Bool) {
        if enabled {
            settings.disabledSourceIDs.remove(id)
        } else {
            settings.disabledSourceIDs.insert(id)
        }
        persistSettings()
    }

    func enableAllSources() {
        guard !settings.disabledSourceIDs.isEmpty else { return }
        settings.disabledSourceIDs.removeAll()
        persistSettings()
    }

    func setRefreshInterval(_ interval: RefreshInterval) {
        guard settings.refreshIntervalMinutes != interval.rawValue else { return }
        settings.refreshIntervalMinutes = interval.rawValue
        persistSettings()
        scheduleAutoRefresh()
    }

    /// Start (or restart) the background loop that pulls `/v1/issues` on the
    /// user's chosen cadence. Called on launch, after backend URL changes, and
    /// when the interval changes.
    func scheduleAutoRefresh() {
        autoRefreshTask?.cancel()
        let interval = settings.refreshInterval
        guard interval != .manualOnly, effectiveBackendURL != nil else { return }
        let nanos = UInt64(interval.rawValue) * 60_000_000_000
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanos)
                if Task.isCancelled { break }
                await self?.refreshIssues()
            }
        }
    }

    /// Bind the ambient briefing route monitor to the current settings state.
    /// Called on launch and whenever the user flips the opt-in.
    func configureAmbientBriefing() {
        ambientMonitor.configure(enabled: settings.ambientMorningBriefingEnabled) { [weak self] in
            guard let self else { return }
            self.ambientPlayRequestID &+= 1
        }
    }

    func setAmbientMorningBriefing(_ enabled: Bool) {
        settings.ambientMorningBriefingEnabled = enabled
        persistSettings()
        ambientMonitor.updateEnabled(enabled)
    }

    func setHyperlocalMode(_ enabled: Bool) {
        settings.hyperlocalMode = enabled
        persistSettings()
    }

    func checkBackendHealth() async {
        guard !isCheckingBackend else { return }
        guard let url = effectiveBackendURL else {
            backendStatus = .mockMode
            return
        }
        isCheckingBackend = true
        backendStatus = .checking
        defer { isCheckingBackend = false }

        let probe = url.appendingPathComponent("healthz")
        var request = URLRequest(url: probe, timeoutInterval: 5)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                backendStatus = .offline(
                    message: "Backend reachable but returned an error.",
                    baseURL: url.absoluteString
                )
                return
            }
            let health = try JSONDecoder().decode(BackendHealth.self, from: data)
            backendStatus = .online(health, baseURL: url.absoluteString)
            // When the backend comes online, pull the sources list right away
            // so the Sources panel and host filter are populated.
            Task { await self.refreshSources() }
        } catch {
            let message = userFacingErrorMessage(error, fallback: "Could not reach backend at \(url.absoluteString).")
            backendStatus = .offline(
                message: message,
                baseURL: url.absoluteString
            )
        }
    }

    // MARK: - Issue refresh

    @discardableResult
    func refreshIssues() async -> Bool {
        guard !isRefreshingIssues else { return false }
        isRefreshingIssues = true
        lastIssueRefreshError = nil
        defer { isRefreshingIssues = false }

        do {
            let result = try await issueService.fetchIssues(for: profile)
            // Merge: live first, then samples if toggle is on.
            let sampleIDs = Set(MockCivicData.allIssues.map(\.id))
            let live = result.issues
            let liveFiltered = live.filter { !sampleIDs.contains($0.id) }
            if settings.showSampleIssues {
                issues = liveFiltered + MockCivicData.allIssues
            } else {
                issues = liveFiltered
            }
            civicBrief = result.brief
            lastIssueRefreshAt = .now
            await rescheduleNotifications()
            detectBookmarkDiffs()
            return true
        } catch {
            let message = userFacingErrorMessage(error, fallback: "Could not load issues.")
            lastIssueRefreshError = message
            markBackendOfflineIfNeeded(error, baseURL: effectiveBackendURL)
            return false
        }
    }

    /// Rebuilds the local-notification deadline reminders from current state.
    /// Called after every refresh + whenever bookmarks/interests change.
    func rescheduleNotifications() async {
        let interests = profile?.interests ?? []
        await CivicNotificationScheduler.shared.reschedule(
            for: issues,
            bookmarked: bookmarkedIssueIDs,
            interests: interests
        )
        // Mirror the OS-level deadline notifications into the in-app inbox so
        // the user can still see what was scheduled even if the system alert
        // was missed or permissions were denied.
        let now = Date.now
        let upcoming = issues.filter { issue in
            guard issue.voteDate > now else { return false }
            if bookmarkedIssueIDs.contains(issue.id) { return true }
            if interests.isEmpty { return false }
            return !issue.topics.isDisjoint(with: interests)
        }
        for issue in upcoming.prefix(20) {
            let id = "inbox.deadline.\(issue.id.uuidString)"
            guard !inboxNotifications.contains(where: { $0.id == id }) else { continue }
            recordInboxNotification(
                .init(
                    id: id,
                    kind: .deadline,
                    title: "Vote scheduled",
                    body: "\(issue.title) — \(shortDateFormatter.string(from: issue.voteDate))",
                    issueID: issue.id,
                    scheduledAtISO: ISO8601DateFormatter().string(from: issue.voteDate),
                    isRead: false,
                ),
            )
        }
    }

    /// Append a notification to the inbox, dedup on id, cap to 100, persist.
    func recordInboxNotification(_ entry: AthenInboxNotification) {
        if let existing = inboxNotifications.firstIndex(where: { $0.id == entry.id }) {
            inboxNotifications[existing] = entry
        } else {
            inboxNotifications.insert(entry, at: 0)
        }
        if inboxNotifications.count > 100 {
            inboxNotifications = Array(inboxNotifications.prefix(100))
        }
        persistInbox()
    }

    func markInboxRead(_ id: String) {
        guard let idx = inboxNotifications.firstIndex(where: { $0.id == id }) else { return }
        guard !inboxNotifications[idx].isRead else { return }
        inboxNotifications[idx].isRead = true
        persistInbox()
    }

    func markAllInboxRead() {
        var changed = false
        for idx in inboxNotifications.indices where !inboxNotifications[idx].isRead {
            inboxNotifications[idx].isRead = true
            changed = true
        }
        if changed { persistInbox() }
    }

    func clearInbox() {
        guard !inboxNotifications.isEmpty else { return }
        inboxNotifications = []
        persistInbox()
    }

    var unreadInboxCount: Int {
        inboxNotifications.filter { !$0.isRead }.count
    }

    private func persistInbox() {
        guard let data = try? JSONEncoder().encode(inboxNotifications) else { return }
        defaults.set(data, forKey: Self.inboxKey)
    }

    private var shortDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    // MARK: - Chat

    func sendChat(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isChatStreaming else { return }

        chatError = nil
        let userMessage = ChatMessage(role: .user, content: trimmed)
        chatMessages.append(userMessage)

        let placeholder = ChatMessage(role: .assistant, content: "", isStreaming: true)
        chatMessages.append(placeholder)
        let placeholderID = placeholder.id

        let history = Array(chatMessages.dropLast())
        let filings = filingSnapshots()
        let issues = visibleIssues
        let userProfile = profile
        let serviceMatches = Array(matchedServices.prefix(5))

        isChatStreaming = true
        chatTask?.cancel()
        chatTask = Task { [chatService] in
            do {
                let stream = chatService.stream(
                    messages: history,
                    profile: userProfile,
                    visibleIssues: issues,
                    filings: filings,
                    matchedServices: serviceMatches
                )

                for try await event in stream {
                    if Task.isCancelled { break }
                    switch event {
                    case let .delta(text):
                        appendDelta(text, to: placeholderID)
                    case let .toolStart(name):
                        markToolRunning(name, on: placeholderID)
                    case let .toolDone(name, summary):
                        markToolDone(name, summary: summary, on: placeholderID)
                    case .done:
                        finalize(placeholderID)
                    case let .error(message):
                        fail(placeholderID, message: message)
                    }
                }
                finalize(placeholderID)
            } catch {
                fail(placeholderID, message: (error as? LocalizedError)?.errorDescription ?? "Chat failed.")
            }
            isChatStreaming = false
        }
    }

    func fetchVoiceSession() async throws -> VoiceSession {
        try await voiceService.fetchSession()
    }

    func cancelChatStream() {
        chatTask?.cancel()
        chatTask = nil
        isChatStreaming = false
        if let last = chatMessages.last, last.isStreaming {
            chatMessages[chatMessages.count - 1].isStreaming = false
            if chatMessages[chatMessages.count - 1].content.isEmpty {
                chatMessages.removeLast()
            }
        }
    }

    func resetChat() {
        cancelChatStream()
        chatMessages.removeAll()
        chatError = nil
    }

    func queueAssistantPrompt(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingAssistantPrompt = trimmed
    }

    func consumePendingAssistantPrompt() -> String? {
        let prompt = pendingAssistantPrompt
        pendingAssistantPrompt = nil
        return prompt
    }

    private func appendDelta(_ text: String, to id: ChatMessage.ID) {
        guard let idx = chatMessages.firstIndex(where: { $0.id == id }) else { return }
        chatMessages[idx].content += text
    }

    /// Show a "Searching the web…" chip on the streaming assistant bubble.
    /// Fires when the model decides to call a tool, before the tool runs.
    private func markToolRunning(_ name: String, on id: ChatMessage.ID) {
        guard let idx = chatMessages.firstIndex(where: { $0.id == id }) else { return }
        let call = ChatToolCall(name: name, status: .running, summary: nil)
        chatMessages[idx].toolCalls.append(call)
    }

    /// Flip the running chip to a check + brief summary once the tool returns.
    /// We mutate the most recent matching call so concurrent tools stay distinct.
    private func markToolDone(_ name: String, summary: String, on id: ChatMessage.ID) {
        guard let idx = chatMessages.firstIndex(where: { $0.id == id }) else { return }
        if let callIdx = chatMessages[idx].toolCalls.lastIndex(where: { $0.name == name && $0.status == .running }) {
            chatMessages[idx].toolCalls[callIdx].status = .done
            chatMessages[idx].toolCalls[callIdx].summary = summary
        } else {
            chatMessages[idx].toolCalls.append(ChatToolCall(name: name, status: .done, summary: summary))
        }
    }

    private func finalize(_ id: ChatMessage.ID) {
        guard let idx = chatMessages.firstIndex(where: { $0.id == id }) else { return }
        chatMessages[idx].isStreaming = false
        if chatMessages[idx].content.isEmpty {
            chatMessages.remove(at: idx)
        }
    }

    private func fail(_ id: ChatMessage.ID, message: String) {
        guard let idx = chatMessages.firstIndex(where: { $0.id == id }) else { return }
        chatMessages[idx].isStreaming = false
        if chatMessages[idx].content.isEmpty {
            chatMessages.remove(at: idx)
        }
        chatError = message
    }

    private func filingSnapshots() -> [ChatFilingSnapshot] {
        filingStatuses.compactMap { entry -> ChatFilingSnapshot? in
            guard
                let receipt = entry.value.receipt,
                let issue = issues.first(where: { $0.id == entry.key })
            else { return nil }
            return ChatFilingSnapshot(
                issueTitle: issue.title,
                action: receipt.action,
                officialName: receipt.officialName,
                sentAt: receipt.sentAt,
                confirmationCode: receipt.confirmationCode
            )
        }
    }

    private func persist(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: Self.profileDefaultsKey)
    }

    /// Picks `HTTPCivicFilingService` when `CIVIC_API_BASE_URL` is set in the run
    /// scheme's environment variables, otherwise falls back to the mock so previews
    /// and unconfigured runs still work.
    nonisolated static func defaultFilingService() -> CivicFilingServicing {
        guard let url = configuredBaseURL() else { return MockCivicFilingService() }
        return HTTPCivicFilingService(baseURL: url)
    }

    nonisolated static func defaultProfileResolver() -> ProfileResolverServicing {
        guard let url = configuredBaseURL() else { return MockProfileResolverService() }
        return HTTPProfileResolverService(baseURL: url)
    }

    nonisolated static func defaultChatService() -> ChatServicing {
        guard let url = configuredBaseURL() else { return MockChatService() }
        return HTTPChatService(baseURL: url)
    }

    nonisolated static func defaultNewsService() -> NewsServicing {
        guard let url = configuredBaseURL() else { return MockNewsService() }
        return HTTPNewsService(baseURL: url)
    }

    nonisolated static func defaultIssueService() -> IssueServicing {
        guard let url = configuredBaseURL() else { return MockIssueService() }
        return HTTPIssueService(baseURL: url)
    }

    nonisolated static func defaultAthenBriefService() -> AthenBriefServicing {
        guard let url = configuredBaseURL() else { return MockAthenBriefService() }
        return HTTPAthenBriefService(baseURL: url)
    }

    nonisolated static func defaultVoiceService() -> VoiceServicing {
        guard let url = configuredBaseURL() else { return MockVoiceService() }
        return HTTPVoiceService(baseURL: url)
    }

    nonisolated static func defaultSourcesService() -> SourcesServicing {
        guard let url = configuredBaseURL() else { return MockSourcesService() }
        return HTTPSourcesService(baseURL: url)
    }

    nonisolated static func defaultRefreshService() -> RefreshServicing {
        guard let url = configuredBaseURL() else { return MockRefreshService() }
        return HTTPRefreshService(baseURL: url)
    }

    nonisolated static func defaultBriefService() -> BriefServicing {
        guard let url = configuredBaseURL() else { return MockBriefService() }
        return HTTPBriefService(baseURL: url)
    }

    nonisolated static func defaultDraftVariantsService() -> DraftVariantsServicing {
        guard let url = configuredBaseURL() else { return MockDraftVariantsService() }
        return HTTPDraftVariantsService(baseURL: url)
    }

    nonisolated static func defaultBallotService() -> BallotServicing {
        guard let url = configuredBaseURL() else { return MockBallotService() }
        return HTTPBallotService(baseURL: url)
    }

    nonisolated static func defaultIntegrationsService() -> IntegrationsServicing {
        guard let url = configuredBaseURL() else { return MockIntegrationsService() }
        return HTTPIntegrationsService(baseURL: url)
    }

    nonisolated static func defaultPetitionsService() -> PetitionsServicing {
        guard let url = configuredBaseURL() else { return MockPetitionsService() }
        return HTTPPetitionsService(baseURL: url)
    }

    nonisolated static func defaultVoterRailService() -> VoterRailServicing {
        guard let url = configuredBaseURL() else { return MockVoterRailService() }
        return HTTPVoterRailService(baseURL: url)
    }

    nonisolated static func defaultLifeEventsService() -> LifeEventsServicing {
        guard let url = configuredBaseURL() else { return MockLifeEventsService() }
        return HTTPLifeEventsService(baseURL: url)
    }

    nonisolated static func defaultDirectoryService() -> OfficialsDirectoryServicing {
        guard let url = configuredBaseURL() else { return MockOfficialsDirectoryService() }
        return HTTPOfficialsDirectoryService(baseURL: url)
    }

    nonisolated static func defaultSpeechService() -> SpeechServicing {
        guard let url = configuredBaseURL() else { return MockSpeechService() }
        return HTTPSpeechService(baseURL: url)
    }

    nonisolated static func defaultModerationService() -> ModerationServicing {
        guard let url = configuredBaseURL() else { return MockModerationService() }
        return HTTPModerationService(baseURL: url)
    }

    nonisolated static func defaultSavedSearchService() -> SavedSearchServicing {
        guard let url = configuredBaseURL() else { return MockSavedSearchService() }
        return HTTPSavedSearchService(baseURL: url)
    }

    nonisolated static func defaultTimelineService() -> TimelineServicing {
        guard let url = configuredBaseURL() else { return MockTimelineService() }
        return HTTPTimelineService(baseURL: url)
    }

    nonisolated static func defaultUrlAnalyzeService() -> UrlAnalyzeServicing {
        guard let url = configuredBaseURL() else { return MockUrlAnalyzeService() }
        return HTTPUrlAnalyzeService(baseURL: url)
    }

    nonisolated static func defaultPersonalImpactService() -> PersonalImpactServicing {
        guard let url = configuredBaseURL() else { return MockPersonalImpactService() }
        return HTTPPersonalImpactService(baseURL: url)
    }

    // MARK: - Impact profile (persisted financial snapshot)

    private static let impactProfileKey = "athen.impact-profile.v1"

    var impactProfile: CivicImpactProfile {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.impactProfileKey),
                  let p = try? JSONDecoder().decode(CivicImpactProfile.self, from: data) else {
                return .empty
            }
            return p
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.impactProfileKey)
            }
        }
    }

    func estimatePersonalImpact(for issueId: String) async -> CivicPersonalImpact? {
        do {
            return try await personalImpactService.estimate(
                issueId: issueId,
                profile: impactProfile,
                zip: profile?.zipCode,
                state: profile?.stateName,
            )
        } catch {
            return nil
        }
    }

    // MARK: - URL analyzer

    func analyzeURL(_ url: String) async -> Result<CivicUrlAnalysis, Error> {
        do {
            let out = try await urlAnalyzeService.analyze(url: url)
            return .success(out)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Predictive nudges

    /// Sync local vote-nudge notifications against the current bookmark set.
    /// Safe to call on app foreground / after refresh.
    func syncPredictiveNudges() {
        let pool = bookmarkedIssues
        Task { @MainActor in
            await PredictiveNudgeScheduler.shared.sync(bookmarkedIssues: pool)
        }
    }

    // MARK: - Filing tally (social proof)

    /// Aggregate endorse / oppose count for one issue. Public, no auth.
    /// Returns nil only if the backend is unreachable.
    func loadFilingTally(issueId: String) async -> IssueFilingTally? {
        guard let baseURL = Self.configuredBaseURL() else { return nil }
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/issues/\(issueId)/tally"))
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await AthenURLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try? JSONDecoder().decode(IssueFilingTally.self, from: data)
        } catch {
            return nil
        }
    }

    /// Record the user's public position on one issue. Bumps the public
    /// tally on the backend and returns the new counts. Decoupled from
    /// email send so positions are always counted — even when no official
    /// is reachable (federal agency rules, ZIP-only state issues, etc.).
    @discardableResult
    func recordPosition(issueId: String, action: CivicAction) async -> IssueFilingTally? {
        guard let baseURL = Self.configuredBaseURL() else { return nil }
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/issues/\(issueId)/position"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let payload: [String: String] = ["action": action.rawValue.lowercased()]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await AthenURLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try? JSONDecoder().decode(IssueFilingTally.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Saved searches

    func loadSavedSearches() async {
        guard !isLoadingSavedSearches else { return }
        isLoadingSavedSearches = true
        lastSavedSearchError = nil
        defer { isLoadingSavedSearches = false }
        do {
            savedSearches = try await savedSearchService.list()
            // Emit an inbox notification for any saved search whose match
            // count is newer than what we'd previously seen. Keeps the
            // alert experience simple: open the app → see new hits.
            for search in savedSearches where search.alertsEnabled && search.freshMatchCount > 0 {
                recordInboxNotification(
                    .init(
                        id: "inbox.saved-search.\(search.id).\(Int(Date.now.timeIntervalSince1970 / 3600))",
                        kind: .systemUpdate,
                        title: "\(search.freshMatchCount) new for \"\(search.name)\"",
                        body: "Tap to review your saved search.",
                        issueID: nil,
                        scheduledAtISO: ISO8601DateFormatter().string(from: .now),
                        isRead: false,
                    ),
                )
            }
        } catch {
            lastSavedSearchError = (error as? LocalizedError)?.errorDescription ?? "Couldn't load saved searches."
        }
    }

    @discardableResult
    func createSavedSearch(name: String, query: String, scope: CivicSavedSearch.Scope, stateCode: String?, alertsEnabled: Bool) async -> CivicSavedSearch? {
        do {
            let response = try await savedSearchService.create(
                name: name,
                query: query,
                scope: scope,
                stateCode: stateCode,
                alertsEnabled: alertsEnabled,
            )
            savedSearches.insert(response.search, at: 0)
            return response.search
        } catch {
            lastSavedSearchError = (error as? LocalizedError)?.errorDescription ?? "Couldn't save search."
            return nil
        }
    }

    func updateSavedSearch(id: String, patch: SavedSearchPatch) async {
        do {
            let updated = try await savedSearchService.update(id: id, patch: patch)
            if let idx = savedSearches.firstIndex(where: { $0.id == id }) {
                savedSearches[idx] = updated
            }
        } catch {
            lastSavedSearchError = (error as? LocalizedError)?.errorDescription ?? "Couldn't update search."
        }
    }

    func deleteSavedSearch(id: String) async {
        do {
            try await savedSearchService.delete(id: id)
            savedSearches.removeAll { $0.id == id }
        } catch {
            lastSavedSearchError = (error as? LocalizedError)?.errorDescription ?? "Couldn't delete search."
        }
    }

    // MARK: - Timeline + CSV export

    func loadTimeline(issueId: String) async -> [CivicTimelineEvent] {
        do {
            return try await timelineService.fetchTimeline(issueId: issueId)
        } catch {
            return []
        }
    }

    func exportIssuesCSV(scope: String?, stateCode: String?, q: String?) async -> Data? {
        do {
            return try await timelineService.exportIssuesCSV(scope: scope, stateCode: stateCode, q: q)
        } catch {
            return nil
        }
    }

    // MARK: - Officials directory

    /// Federal members of Congress + executive branch officials. Always
    /// available to every user, no ZIP required.
    @discardableResult
    func loadFederalDirectory(force: Bool = false) async -> Bool {
        guard force || federalDirectory.isEmpty else { return true }
        guard !isLoadingDirectory else { return false }
        isLoadingDirectory = true
        lastDirectoryError = nil
        defer { isLoadingDirectory = false }
        do {
            federalDirectory = try await directoryService.federal()
            return true
        } catch {
            lastDirectoryError = (error as? LocalizedError)?.errorDescription ?? "Couldn't load federal directory."
            return false
        }
    }

    /// State legislators + governor for a state. Lazily loaded.
    @discardableResult
    func loadStateDirectory(_ stateCode: String, force: Bool = false) async -> Bool {
        let code = stateCode.uppercased()
        if !force, let cached = stateDirectoryByCode[code], !cached.isEmpty { return true }
        do {
            let list = try await directoryService.state(code)
            stateDirectoryByCode[code] = list
            return true
        } catch {
            lastDirectoryError = (error as? LocalizedError)?.errorDescription ?? "Couldn't load state directory."
            return false
        }
    }

    func searchDirectory(_ query: String) async -> [DirectoryOfficial] {
        do {
            return try await directoryService.search(query)
        } catch {
            return []
        }
    }

    func directoryDetail(id: String) async -> DirectoryOfficial? {
        do {
            return try await directoryService.detail(id: id)
        } catch {
            // Fall back to whatever we have cached.
            return federalDirectory.first(where: { $0.id == id })
                ?? stateDirectoryByCode.values.flatMap({ $0 }).first(where: { $0.id == id })
        }
    }

    /// My-reps view: pulls federal members representing the user's state +
    /// any state directory entries for that ZIP.
    var myReps: [DirectoryOfficial] {
        guard let state = profile?.stateCode.uppercased() else { return [] }
        let federal = federalDirectory.filter { $0.state == state || $0.chamber == .executive }
        let stateList = stateDirectoryByCode[state] ?? []
        return federal + stateList
    }

    func toggleBookmarkOfficial(_ id: String) {
        if bookmarkedOfficialIDs.contains(id) {
            bookmarkedOfficialIDs.remove(id)
        } else {
            bookmarkedOfficialIDs.insert(id)
        }
        persistBookmarkedOfficials()
    }

    func isOfficialBookmarked(_ id: String) -> Bool {
        bookmarkedOfficialIDs.contains(id)
    }

    private func persistBookmarkedOfficials() {
        guard let data = try? JSONEncoder().encode(Array(bookmarkedOfficialIDs)) else { return }
        defaults.set(data, forKey: Self.bookmarkedOfficialsKey)
    }

    // MARK: - Life-event planner

    func generateLifeEventPlan(description: String) async throws -> CivicLifeEventPlan {
        guard !isGeneratingLifeEventPlan else {
            throw CivicFilingError.server(status: 0, message: "Already generating a plan.")
        }
        isGeneratingLifeEventPlan = true
        lastLifeEventError = nil
        defer { isGeneratingLifeEventPlan = false }

        let householdInt: Int? = {
            switch profile?.householdSize {
            case .one: return 1
            case .two: return 2
            case .threeOrFour: return 3
            case .fivePlus: return 5
            case .none, .unknown, .some(.unknown): return nil
            default: return nil
            }
        }()
        let profileInput = LifeEventProfileInput(
            stateCode: profile?.stateCode,
            stateName: profile?.stateName,
            zip: profile?.zipCode,
            locality: profile?.localityLabel,
            factors: profile.map { Array($0.factors).map(\.rawValue) },
            householdSize: householdInt,
            incomeBand: profile?.incomeBand.label
        )

        do {
            let plan = try await lifeEventsService.plan(description: description, profile: profileInput)
            lifeEventPlans.insert(plan, at: 0)
            // Cap at 20 stored plans to keep UserDefaults sane.
            if lifeEventPlans.count > 20 {
                lifeEventPlans = Array(lifeEventPlans.prefix(20))
            }
            persistLifeEventPlans()
            return plan
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Couldn't generate plan."
            lastLifeEventError = message
            throw error
        }
    }

    func deleteLifeEventPlan(_ planID: String) {
        lifeEventPlans.removeAll { $0.id == planID }
        persistLifeEventPlans()
    }

    private func persistLifeEventPlans() {
        guard let data = try? JSONEncoder().encode(lifeEventPlans) else { return }
        defaults.set(data, forKey: Self.lifeEventPlansKey)
    }

    // MARK: - Voter rail

    /// Cached state — voter rail views read from here, then call `loadVoterRail`
    /// to refresh from the backend.
    var upcomingElections: [CivicElection] = []
    var pollingPlaceInfo: CivicPollingPlaceResponse?
    var sampleBallotResponse: CivicBallotResponse?
    var registrationInfo: StateRegistrationInfo?
    var repScorecard: RepScorecardResponse?
    var isLoadingVoterRail: Bool = false
    var lastVoterRailError: String?

    /// Soonest upcoming election for the user's address, derived from the cache.
    var nextElection: CivicElection? {
        upcomingElections
            .filter { ($0.daysUntil ?? -1) >= 0 }
            .min(by: { ($0.daysUntil ?? Int.max) < ($1.daysUntil ?? Int.max) })
    }

    var isElectionDay: Bool {
        nextElection?.isToday ?? false
    }

    func loadVoterRail(force: Bool = false) async {
        guard !isLoadingVoterRail else { return }
        isLoadingVoterRail = true
        lastVoterRailError = nil
        defer { isLoadingVoterRail = false }

        let zip = profile?.zipCode
        let state = profile?.stateCode

        // Elections list is the cheapest call — always do it first.
        do {
            let electionsResult = try await voterRailService.listElections()
            upcomingElections = electionsResult.elections
        } catch {
            lastVoterRailError = (error as? LocalizedError)?.errorDescription ?? "Couldn't load elections."
        }

        // Polling + registration in parallel.
        if let zip {
            do {
                pollingPlaceInfo = try await voterRailService.pollingPlace(zip: zip)
            } catch {
                // Soft-fail: polling lookup is informational.
            }
        }
        if let state {
            do {
                registrationInfo = try await voterRailService.registration(stateCode: state)
            } catch {
                // Soft-fail: static data; missing state is rare.
            }
        }

        // Optional second pass: load the next election's sample ballot.
        if force || sampleBallotResponse == nil {
            if let zip {
                do {
                    let ballotResp = try await voterRailService.ballot(zip: zip, electionId: nextElection?.id)
                    sampleBallotResponse = ballotResp
                } catch {
                    // Soft-fail: ballot is a long-running call.
                }
            }
        }
    }

    func loadSampleBallot(electionId: String?) async {
        guard let zip = profile?.zipCode else { return }
        do {
            let ballot = try await voterRailService.ballot(zip: zip, electionId: electionId)
            sampleBallotResponse = ballot
        } catch {
            lastVoterRailError = (error as? LocalizedError)?.errorDescription ?? "Couldn't load sample ballot."
        }
    }

    func loadRepScorecard() async {
        let formatter = ISO8601DateFormatter()
        let inputs = filingHistory.map { entry in
            ScorecardFilingInput(
                issueId: entry.issue.id.uuidString,
                issueTitle: entry.issue.title,
                position: entry.receipt.action == .endorse ? "endorse" : "oppose",
                filedAtISO: formatter.string(from: entry.receipt.sentAt),
                officialName: entry.receipt.officialName
            )
        }
        do {
            repScorecard = try await voterRailService.scorecard(filings: inputs)
        } catch {
            lastVoterRailError = (error as? LocalizedError)?.errorDescription ?? "Couldn't load rep scorecard."
        }
    }

    // MARK: - Filing follow-through
    //
    // Once the user files on a bill, Athen should close the loop when the
    // vote actually happens. This computed walks the repScorecard history
    // and surfaces any votes that came AFTER the user filed — these are the
    // "your rep voted X on the bill you filed about" moments. Shown on Home
    // as "Updates on your filings" until the user dismisses each one.

    struct FilingFollowUp: Identifiable, Hashable {
        let issueId: String
        let issueTitle: String
        let userPosition: String  // "endorse" or "oppose"
        let officialName: String
        let officialVote: String  // "yes" / "no" / "abstain"
        let voteDate: Date
        let aligned: Bool
        var id: String { issueId + officialName }
    }

    /// Returns recent vote outcomes for bills the user filed on. Sorted newest first.
    var recentFilingFollowUps: [FilingFollowUp] {
        guard let scorecards = repScorecard?.scorecards else { return [] }
        let cutoff = previousLastOpenedAt ?? Date.distantPast
        var out: [FilingFollowUp] = []
        for card in scorecards {
            for entry in card.history {
                guard let voteDateISO = entry.voteDateISO,
                      let voteDate = ISO8601DateFormatter().date(from: voteDateISO),
                      let vote = entry.vote,
                      voteDate > cutoff
                else { continue }
                let aligned = (entry.position == "endorse" && vote == "yes")
                    || (entry.position == "oppose" && vote == "no")
                out.append(FilingFollowUp(
                    issueId: entry.issueId,
                    issueTitle: entry.issueTitle,
                    userPosition: entry.position,
                    officialName: card.officialName,
                    officialVote: vote,
                    voteDate: voteDate,
                    aligned: aligned
                ))
            }
        }
        return out.sorted { $0.voteDate > $1.voteDate }
    }

    var hasRecentFollowUps: Bool {
        !recentFilingFollowUps.isEmpty
    }

    // MARK: - Petitions

    func petition(with id: String) -> CivicPetition? {
        petitions.first { $0.id == id }
    }

    /// Petitions linked to a specific civic issue — used by IssueDetailView
    /// to show a "petitions on this" rail.
    func petitions(for issueId: CivicIssue.ID) -> [CivicPetition] {
        petitions.filter { $0.attachedIssueId == issueId.uuidString }
    }

    @discardableResult
    func loadPetitions(_ filter: PetitionFilter? = nil) async -> Bool {
        guard !isLoadingPetitions else { return false }
        isLoadingPetitions = true
        lastPetitionError = nil
        defer { isLoadingPetitions = false }
        let activeFilter = filter ?? petitionFilter
        do {
            let response = try await petitionsService.list(
                entityId: integrationEntityID,
                filter: activeFilter
            )
            petitions = response.items
            petitionStats = response.stats
            if let viewer = response.viewer {
                signedPetitionIDs = Set(viewer.signedIds)
                createdPetitionIDs = Set(viewer.createdIds)
            }
            if filter != nil { petitionFilter = activeFilter }
            return true
        } catch {
            lastPetitionError = (error as? LocalizedError)?.errorDescription ?? "Couldn't load petitions."
            return false
        }
    }

    func signPetition(_ petitionID: String, name: String, zip: String, comment: String?) async throws -> CivicPetition {
        let updated = try await petitionsService.sign(
            id: petitionID,
            entityId: integrationEntityID,
            name: name,
            zip: zip,
            comment: comment
        )
        replacePetitionInState(updated)
        signedPetitionIDs.insert(updated.id)
        return updated
    }

    func unsignPetition(_ petitionID: String) async {
        do {
            if let updated = try await petitionsService.unsign(id: petitionID, entityId: integrationEntityID) {
                replacePetitionInState(updated)
            }
            signedPetitionIDs.remove(petitionID)
        } catch {
            lastPetitionError = (error as? LocalizedError)?.errorDescription ?? "Couldn't unsign."
        }
    }

    func createPetition(_ input: PetitionCreateInput) async throws -> CivicPetition {
        let petition = try await petitionsService.create(
            entityId: integrationEntityID,
            input: input
        )
        petitions.insert(petition, at: 0)
        createdPetitionIDs.insert(petition.id)
        signedPetitionIDs.insert(petition.id)
        return petition
    }

    func deliverPetitionNow(_ petitionID: String) async throws -> CivicPetitionDeliveryResult {
        let result = try await petitionsService.deliver(id: petitionID, entityId: integrationEntityID)
        // Refresh the local copy so the UI reflects the new status.
        if let detail = try? await petitionsService.detail(id: petitionID, entityId: integrationEntityID) {
            replacePetitionInState(detail.petition)
            // Fire Notion / Discord automations if configured.
            onPetitionDelivered(detail.petition)
        }
        return result
    }

    func deletePetition(_ petitionID: String) async {
        do {
            try await petitionsService.delete(id: petitionID, entityId: integrationEntityID)
            petitions.removeAll { $0.id == petitionID }
            createdPetitionIDs.remove(petitionID)
            signedPetitionIDs.remove(petitionID)
        } catch {
            lastPetitionError = (error as? LocalizedError)?.errorDescription ?? "Couldn't delete petition."
        }
    }

    private func replacePetitionInState(_ petition: CivicPetition) {
        if let idx = petitions.firstIndex(where: { $0.id == petition.id }) {
            petitions[idx] = petition
        } else {
            petitions.insert(petition, at: 0)
        }
    }

    /// Sends OCR-extracted ballot text to the backend for plain-English
    /// per-item briefs. One-shot — no caching since each ballot is unique.
    func analyzeBallot(text: String) async throws -> BallotAnalysis {
        try await ballotService.analyze(text: text)
    }

    // MARK: - Integrations (Composio)

    /// Whether the user wants outbound filings routed through their personal
    /// Gmail (via Composio) instead of the default backend mailer.
    var isGmailFilingEnabled: Bool {
        defaults.bool(forKey: Self.gmailFilingEnabledKey)
    }

    /// "Has the user ever explicitly set the Gmail-filing toggle themselves?"
    /// We use this to auto-enable Gmail filing on the *first* time we detect
    /// a Composio Gmail connection — because the user only goes through that
    /// OAuth flow if they want their filings sent for real. Once the user
    /// has touched the toggle directly, we respect their choice forever and
    /// never auto-flip it again.
    private static let gmailFilingUserChosenKey = "athen.gmail-filing-user-chosen.v1"

    var hasUserChosenGmailFilingPreference: Bool {
        defaults.bool(forKey: Self.gmailFilingUserChosenKey)
    }

    func setGmailFilingEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.gmailFilingEnabledKey)
        defaults.set(true, forKey: Self.gmailFilingUserChosenKey)
        // Rebuild the filing service so the next send picks up the new flag.
        rebuildServices()
    }

    var connectedGmailConnectionId: String? {
        let status = integrationStatusByApp["gmail"]
        guard status?.isConnected == true else { return nil }
        return status?.connectionId
    }

    var isGmailConnected: Bool {
        integrationStatusByApp["gmail"]?.isConnected == true
    }

    @discardableResult
    func loadIntegrations() async -> Bool {
        guard !isLoadingIntegrations else { return false }
        isLoadingIntegrations = true
        integrationsError = nil
        defer { isLoadingIntegrations = false }
        do {
            let catalog = try await integrationsService.fetchCatalog()
            integrationCatalog = catalog.apps
            // Only fetch status if Composio is enabled on the backend.
            guard catalog.enabled else {
                integrationStatusByApp = [:]
                return true
            }
            let list = try await integrationsService.fetchStatus(entityId: integrationEntityID)
            var byApp: [String: CivicIntegrationStatus] = [:]
            for item in list.items {
                byApp[item.appName] = item
            }
            integrationStatusByApp = byApp
            // Auto-enable Gmail filing the first time we detect a Composio
            // Gmail connection — the user only goes through OAuth if they
            // want filings sent for real. Respects any explicit toggle the
            // user has set in DraftFilingSheet / settings.
            let gmailNowConnected = byApp["gmail"]?.isConnected == true
            if gmailNowConnected && !hasUserChosenGmailFilingPreference {
                defaults.set(true, forKey: Self.gmailFilingEnabledKey)
                defaults.set(true, forKey: Self.gmailFilingUserChosenKey)
            }
            // Pick up the new connection state in the filing service.
            rebuildServices()
            return true
        } catch {
            integrationsError = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach integrations."
            return false
        }
    }

    func connectIntegration(_ appName: String) async throws -> URL {
        let result = try await integrationsService.connect(entityId: integrationEntityID, appName: appName)
        guard let url = URL(string: result.redirectUrl) else {
            throw CivicFilingError.server(status: 0, message: "Composio returned a malformed redirect URL.")
        }
        return url
    }

    func disconnectIntegration(_ appName: String) async {
        guard let connectionId = integrationStatusByApp[appName]?.connectionId else { return }
        do {
            try await integrationsService.disconnect(connectionId: connectionId)
            integrationStatusByApp[appName] = CivicIntegrationStatus(
                appName: appName,
                isConnected: false,
                connectionId: nil,
                status: nil
            )
            if appName == "gmail" { setGmailFilingEnabled(false) }
        } catch {
            integrationsError = (error as? LocalizedError)?.errorDescription ?? "Couldn't disconnect."
        }
    }

    /// Routes a filing through the user's connected Gmail when they've opted
    /// in. Falls back silently to the standard dispatcher if the toggle is
    /// off, Gmail isn't connected, or the Composio call fails.
    func sendFilingViaGmail(to: String, subject: String, body: String) async throws {
        try await integrationsService.sendGmail(
            entityId: integrationEntityID,
            to: to,
            subject: subject,
            body: body
        )
    }

    // MARK: - Automation settings + dispatch

    var connectedAppNames: Set<String> {
        Set(integrationStatusByApp.values.filter { $0.isConnected }.map(\.appName))
    }

    func updateIntegrationSettings(_ updater: (inout CivicIntegrationSettings) -> Void) {
        var next = integrationSettings
        updater(&next)
        integrationSettings = next
        persistIntegrationSettings()
    }

    private func persistIntegrationSettings() {
        guard let data = try? JSONEncoder().encode(integrationSettings) else { return }
        defaults.set(data, forKey: Self.integrationSettingsKey)
    }

    /// Fires a typed automation. Soft-fails when the prerequisite isn't met
    /// (app not connected, target not configured) so callers can call
    /// liberally without guarding each time.
    func runAutomationSafely(_ automation: String, input: AutomationInputPayload, requires connectedApp: String) async {
        guard connectedAppNames.contains(connectedApp) else { return }
        do {
            try await integrationsService.runAutomation(
                entityId: integrationEntityID,
                automation: automation,
                input: input
            )
        } catch {
            // Surface in integrationsError but don't propagate — automations
            // shouldn't fail the user's primary action.
            integrationsError = "Automation \(automation) failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    // MARK: - Event hooks

    /// Called from toggleBookmark when a new bookmark is added. Fires the
    /// calendar-event automation if enabled.
    func onBookmarkAdded(_ issue: CivicIssue) {
        guard integrationSettings.calendarOnBookmark else { return }
        Task {
            let iso = ISO8601DateFormatter()
            var input = AutomationInputPayload()
            input.title = "Vote on: \(issue.title)"
            input.startISO = iso.string(from: issue.voteDate)
            input.endISO = iso.string(from: issue.voteDate.addingTimeInterval(3600))
            input.notes = "\(issue.summary)\n\nTracked via Athen — open the app to file your position."
            input.location = issue.jurisdiction
            await runAutomationSafely("calendar_event", input: input, requires: "googlecalendar")
        }
    }

    /// Called after a successful filing send. Fires Notion log + social
    /// post automations as configured.
    func onFilingSent(issue: CivicIssue, action: CivicAction, receipt: FilingReceipt) {
        let s = integrationSettings
        Task {
            if s.notionOnFiling && !s.notionDatabaseId.isEmpty {
                var input = AutomationInputPayload()
                input.databaseId = s.notionDatabaseId
                input.pageTitle = "\(action == .endorse ? "Endorsed" : "Opposed"): \(issue.title)"
                input.properties = [
                    "Name": .rich([.init(text: .init(content: "\(action == .endorse ? "Endorsed" : "Opposed"): \(issue.title)"))]),
                ]
                await runAutomationSafely("notion_log", input: input, requires: "notion")
            }
            if s.twitterOnFiling {
                var input = AutomationInputPayload()
                let verb = action == .endorse ? "endorsed" : "opposed"
                input.body = "I just \(verb) \"\(issue.title)\" — filed with \(receipt.officialName) through @AthenCivic."
                input.hashtags = parseHashtags(s.socialHashtags)
                await runAutomationSafely("twitter_post", input: input, requires: "twitter")
            }
            if s.linkedinOnFiling {
                var input = AutomationInputPayload()
                let verb = action == .endorse ? "endorsed" : "opposed"
                input.body = "Civic action: I just \(verb) \"\(issue.title)\" and filed my position with \(receipt.officialName).\n\nTracked through Athen."
                await runAutomationSafely("linkedin_post", input: input, requires: "linkedin")
            }
        }
    }

    /// Called when a petition is delivered (worker or manual). Fires Notion
    /// + Discord automations as configured.
    func onPetitionDelivered(_ petition: CivicPetition) {
        let s = integrationSettings
        Task {
            if s.notionOnPetition && !s.notionDatabaseId.isEmpty {
                var input = AutomationInputPayload()
                input.databaseId = s.notionDatabaseId
                input.pageTitle = "Petition delivered: \(petition.title)"
                input.properties = [
                    "Name": .rich([.init(text: .init(content: "Petition delivered: \(petition.title)"))]),
                ]
                await runAutomationSafely("notion_log", input: input, requires: "notion")
            }
            if s.discordOnPetition && !s.discordChannelId.isEmpty {
                var input = AutomationInputPayload()
                input.channel = s.discordChannelId
                input.text = "**Petition delivered.** \"\(petition.title)\" went to \(petition.targets.map(\.officialName).joined(separator: ", ")) with \(petition.signerCount) signatures."
                await runAutomationSafely("discord_message", input: input, requires: "discord")
            }
        }
    }

    /// Called when a group letter is marked sent. Fires Slack + Discord
    /// automations as configured.
    func onGroupLetterSent(_ letter: GroupLetter) {
        let s = integrationSettings
        Task {
            if s.slackOnGroupLetter && !s.slackChannel.isEmpty {
                var input = AutomationInputPayload()
                input.channel = s.slackChannel
                input.text = ":envelope_with_arrow: Group letter sent: *\(letter.subject)* — \(letter.signerCount) co-signers from your Athen crew."
                await runAutomationSafely("slack_message", input: input, requires: "slack")
            }
            if s.discordOnGroupLetter && !s.discordChannelId.isEmpty {
                var input = AutomationInputPayload()
                input.channel = s.discordChannelId
                input.text = "**Group letter sent.** \"\(letter.subject)\" went out with \(letter.signerCount) co-signers."
                await runAutomationSafely("discord_message", input: input, requires: "discord")
            }
        }
    }

    private func parseHashtags(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Filing tone variants

    func loadDraftVariants(for action: CivicAction, issue: CivicIssue) async {
        guard let profile else { return }
        guard !generatingVariantsFor.contains(issue.id) else { return }
        generatingVariantsFor.insert(issue.id)
        lastVariantError = nil
        defer { generatingVariantsFor.remove(issue.id) }
        do {
            let variants = try await draftVariantsService.fetchVariants(
                action: action,
                issue: issue,
                zip: profile.zipCode,
                stateCode: profile.stateCode,
                locality: profile.localityLabel
            )
            draftVariants[issue.id] = variants
        } catch {
            lastVariantError = (error as? LocalizedError)?.errorDescription ?? "Tone variants failed."
        }
    }

    private nonisolated static func configuredBaseURL() -> URL? {
        // 1. Per-process override — useful for E2E tests + reviewers.
        if let raw = ProcessInfo.processInfo.environment["CIVIC_API_BASE_URL"],
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        // 2. Compile-time Info.plist override — set ATHEN_API_BASE_URL via
        //    xcconfig per environment (Debug/Release) so prod builds hit
        //    the live backend automatically without runtime env vars.
        if let raw = Bundle.main.object(forInfoDictionaryKey: "ATHEN_API_BASE_URL") as? String,
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        #if DEBUG
        // Simulator / dev builds fall back to the local backend so refresh
        // and briefs just work without making the operator configure
        // anything. Release builds DO NOT — they require the Info.plist
        // value above or the in-app Settings override (Backend URL row).
        if let local = URL(string: "http://localhost:8787") {
            return local
        }
        #endif
        return nil
    }
}
