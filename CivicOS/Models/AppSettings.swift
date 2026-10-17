import Foundation

struct AppSettings: Equatable, Hashable, Codable {
    var showSampleIssues: Bool
    var hasCompletedOnboarding: Bool
    /// User-supplied backend base URL (e.g. http://localhost:8787). When nil,
    /// the app falls back to `CIVIC_API_BASE_URL` from the launch environment,
    /// and if that is also missing, to the bundled mock services.
    var backendURL: String?
    /// Source IDs the user has hidden locally. The backend still ingests them;
    /// the device just filters them out of the visible issue list.
    var disabledSourceIDs: Set<String>
    /// How often the Home view auto-refreshes issues from the backend.
    var refreshIntervalMinutes: Int
    /// When true, the app watches for AirPods/CarPlay coming online in the
    /// morning and auto-starts the audio briefing. Opt-in only.
    var ambientMorningBriefingEnabled: Bool
    /// "Hyperlocal mode" — only show city + state items in the Home feed,
    /// hide federal-scope items. Useful for people who only care about
    /// their immediate jurisdiction. Off by default — federal items affect
    /// everyone and we want them in the default mix.
    var hyperlocalMode: Bool

    init(
        showSampleIssues: Bool = false,
        hasCompletedOnboarding: Bool = false,
        backendURL: String? = nil,
        disabledSourceIDs: Set<String> = [],
        refreshIntervalMinutes: Int = RefreshInterval.hourly.rawValue,
        ambientMorningBriefingEnabled: Bool = false,
        hyperlocalMode: Bool = false
    ) {
        self.showSampleIssues = showSampleIssues
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.backendURL = backendURL
        self.disabledSourceIDs = disabledSourceIDs
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.ambientMorningBriefingEnabled = ambientMorningBriefingEnabled
        self.hyperlocalMode = hyperlocalMode
    }

    var refreshInterval: RefreshInterval {
        RefreshInterval(rawValue: refreshIntervalMinutes) ?? .hourly
    }

    /// Tolerate older persisted payloads that lack the new keys.
    enum CodingKeys: String, CodingKey {
        case showSampleIssues
        case hasCompletedOnboarding
        case backendURL
        case disabledSourceIDs
        case refreshIntervalMinutes
        case ambientMorningBriefingEnabled
        case hyperlocalMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showSampleIssues = (try? c.decode(Bool.self, forKey: .showSampleIssues)) ?? false
        hasCompletedOnboarding = (try? c.decode(Bool.self, forKey: .hasCompletedOnboarding)) ?? false
        backendURL = try? c.decodeIfPresent(String.self, forKey: .backendURL)
        disabledSourceIDs = (try? c.decode(Set<String>.self, forKey: .disabledSourceIDs)) ?? []
        refreshIntervalMinutes = (try? c.decode(Int.self, forKey: .refreshIntervalMinutes)) ?? RefreshInterval.hourly.rawValue
        ambientMorningBriefingEnabled = (try? c.decode(Bool.self, forKey: .ambientMorningBriefingEnabled)) ?? false
        hyperlocalMode = (try? c.decode(Bool.self, forKey: .hyperlocalMode)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(showSampleIssues, forKey: .showSampleIssues)
        try c.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try c.encodeIfPresent(backendURL, forKey: .backendURL)
        try c.encode(disabledSourceIDs, forKey: .disabledSourceIDs)
        try c.encode(refreshIntervalMinutes, forKey: .refreshIntervalMinutes)
        try c.encode(ambientMorningBriefingEnabled, forKey: .ambientMorningBriefingEnabled)
        try c.encode(hyperlocalMode, forKey: .hyperlocalMode)
    }

    static let `default` = AppSettings()
}

/// Live snapshot of `/healthz` so the UI can show whether the backend is
/// reachable and which optional integrations are wired.
struct BackendHealth: Equatable, Hashable, Codable {
    let status: String
    let model: String
    let email: String
    let dryRun: Bool
    let stateLegislators: String
    let firecrawl: String
    let voice: String
    let scheduler: String
    let sources: Int
}

enum BackendStatus: Equatable {
    case unknown
    case checking
    case mockMode
    case online(BackendHealth, baseURL: String)
    case offline(message: String, baseURL: String)

    var shortLabel: String {
        switch self {
        case .unknown: return "Unknown"
        case .checking: return "Checking…"
        case .mockMode: return "Mock mode"
        case .online: return "Connected"
        case .offline: return "Offline"
        }
    }
}
