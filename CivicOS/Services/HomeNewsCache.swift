import Foundation

/// On-disk cache of the Home > News tab content (headlines + Claude
/// summary). HomeView reads from this at init so switching away and back —
/// or quitting + relaunching the app — preserves what the user was
/// reading. Only invalidated when the user taps the reload button (which
/// overwrites the cache with fresh content).
final class HomeNewsCache {
    static let shared = HomeNewsCache()

    private let defaults: UserDefaults
    private let itemsKey = "athen.home.news.items.v1"
    private let summaryKey = "athen.home.news.summary.v1"
    private let savedAtKey = "athen.home.news.savedAt.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadItems() -> [NewsHeadline] {
        guard let data = defaults.data(forKey: itemsKey),
              let items = try? JSONDecoder().decode([NewsHeadline].self, from: data) else {
            return []
        }
        return items
    }

    func loadSummary() -> String? {
        let raw = defaults.string(forKey: summaryKey)
        return (raw?.isEmpty ?? true) ? nil : raw
    }

    var savedAt: Date? {
        guard let raw = defaults.object(forKey: savedAtKey) as? Date else { return nil }
        return raw
    }

    func save(items: [NewsHeadline], summary: String?) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: itemsKey)
        }
        if let summary, !summary.isEmpty {
            defaults.set(summary, forKey: summaryKey)
        } else {
            defaults.removeObject(forKey: summaryKey)
        }
        defaults.set(Date.now, forKey: savedAtKey)
    }
}
