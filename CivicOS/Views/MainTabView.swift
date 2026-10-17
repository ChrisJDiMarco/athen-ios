import SwiftUI

struct MainTabView: View {
    @Environment(CivicOSStore.self) private var store
    @State private var selectedTab: Tab = .home
    @State private var deepLinkedIssue: CivicIssue?

    enum Tab: Hashable {
        case home, radar, act, square, assistant
        // Legacy aliases for deep-link compatibility — Brief content moved
        // into Home, Vote merged into Act, You moved behind Radar.
        static let brief: Tab = .home
        static let vote: Tab = .act
        static let feed: Tab = .square
        static let help: Tab = .home
        static let you: Tab = .radar
    }

    private var actTabLabel: String { "Act" }

    private var actTabIcon: String {
        store.isElectionDay ? "hand.raised.fill" : "hand.raised"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectTab: select)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            NavigationStack {
                DashboardView()
                    .navigationDestination(for: CivicIssue.ID.self) { id in
                        if let issue = store.issue(with: id) {
                            IssueDetailView(issue: issue)
                        }
                    }
            }
            .tabItem { Label("Radar", systemImage: "dot.radiowaves.left.and.right") }
            .tag(Tab.radar)

            ActTabView()
                .tabItem { Label(actTabLabel, systemImage: actTabIcon) }
                .tag(Tab.act)
                .badge(store.isElectionDay ? "!" : nil)

            SocialFeedView()
                .tabItem { Label("Square", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(Tab.square)

            ChatView()
                .tabItem { Label("Athen", systemImage: "sparkles") }
                .tag(Tab.assistant)
        }
        .tint(CivicTheme.cyan)
        .preferredColorScheme(.light)
        .onAppear(perform: applyTabBarStyling)
        .onChange(of: store.pendingDeepLinkIssueID) { _, newValue in
            guard let id = newValue, let issue = store.issue(with: id) else { return }
            deepLinkedIssue = issue
            _ = store.consumePendingDeepLink()
        }
        .onChange(of: store.pendingAssistantPrompt) { _, newValue in
            guard newValue != nil else { return }
            selectedTab = .assistant
        }
        .onChange(of: store.pendingSocialIssueID) { _, newValue in
            guard newValue != nil else { return }
            selectedTab = .square
        }
        .onChange(of: store.pendingFeedOpen) { _, newValue in
            guard newValue, store.consumePendingFeedOpen() else { return }
            selectedTab = .square
        }
        .onChange(of: store.pendingHelpOpen) { _, newValue in
            guard newValue, store.consumePendingHelpOpen() else { return }
            selectedTab = .home
        }
        .sheet(item: $deepLinkedIssue) { issue in
            NavigationStack {
                IssueDetailView(issue: issue)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { deepLinkedIssue = nil }
                                .foregroundStyle(CivicTheme.cyan)
                        }
                    }
            }
            .environment(store)
        }
    }

    private func select(_ tab: Tab) {
        selectedTab = tab
    }

    private func askAssistant(_ prompt: String) {
        store.queueAssistantPrompt(prompt)
        selectedTab = .assistant
    }

    private func applyTabBarStyling() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor(red: 1.0, green: 0.997, blue: 0.984, alpha: 0.96)
        appearance.shadowColor = UIColor(red: 0.886, green: 0.871, blue: 0.835, alpha: 0.9)

        let mutedIcon = UIColor(red: 0.612, green: 0.643, blue: 0.690, alpha: 1.0)
        let activeTint = UIColor(red: 0.078, green: 0.722, blue: 0.651, alpha: 1.0)

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = mutedIcon
        itemAppearance.normal.titleTextAttributes = [
            .foregroundColor: mutedIcon,
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]
        itemAppearance.selected.iconColor = activeTint
        itemAppearance.selected.titleTextAttributes = [
            .foregroundColor: activeTint,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]
        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    MainTabView()
        .environment(CivicOSStore())
}
