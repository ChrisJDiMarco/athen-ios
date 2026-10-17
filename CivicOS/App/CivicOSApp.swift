import SwiftUI

@main
struct CivicOSApp: App {
    @State private var store = CivicOSStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    _ = store.handleDeepLink(url)
                }
                .task {
                    // Bump the civic streak counter for today and capture
                    // last-opened-at before any other refresh logic runs.
                    store.touchStreak()
                    // Kick the auto-refresh loop on whatever cadence the user
                    // last picked. Safe no-op if interval == .manualOnly or no
                    // backend is configured.
                    store.scheduleAutoRefresh()
                    // Surface backend connectivity on Home immediately instead
                    // of waiting for the user to visit the You tab.
                    await store.checkBackendHealth()
                    // Hook the AirPods/CarPlay listener if the user opted in.
                    // No-op when the toggle is off.
                    store.configureAmbientBriefing()
                    // Streak insurance: if user has an active streak, schedule
                    // an 8pm reminder so a bad day doesn't break the chain.
                    await CivicNotificationScheduler.shared.scheduleStreakInsurance(
                        currentStreakDays: store.civicStreakDays
                    )
                }
        }
    }
}

private struct RootView: View {
    @Environment(CivicOSStore.self) private var store

    var body: some View {
        if !store.settings.hasCompletedOnboarding {
            OnboardingView()
                .transition(.opacity)
        } else {
            MainTabView()
                .transition(.opacity)
        }
    }
}
