import SwiftUI

struct OnboardingView: View {
    @Environment(CivicOSStore.self) private var store
    @State private var page: Int = 0
    @State private var zipDraft: String = ""
    @State private var selectedInterests: Set<CivicTopic> = []
    @State private var selectedFactors: Set<CivicProfileFactor> = []
    @State private var notificationsRequested: Bool = false
    @State private var notificationsGranted: Bool = false
    @FocusState private var zipFocused: Bool

    // Onboarding compressed from 7 steps to 3. The intro screens that used
    // to live here told the user what Athen does — but it's faster to SHOW
    // them, not tell. Single welcome page now, then ZIP, then notifications.
    // Interests + factors moved to "personalize" prompts after first feed.
    private let pages = [
        OnboardingPage(
            symbol: "sparkles",
            tint: CivicTheme.cyan,
            title: "Athen — your civic OS.",
            body: "Every bill, vote, election, and program that affects you — in plain English. Tap one button to act. Today Athen covers 50 states and 13 major cities. We'll add yours next."
        )
    ]

    var body: some View {
        ZStack {
            CivicTheme.screenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    if page < pages.count {
                        TabView(selection: $page) {
                            ForEach(pages.indices, id: \.self) { idx in
                                pageView(pages[idx])
                                    .tag(idx)
                                    .padding(.horizontal, 26)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .indexViewStyle(.page(backgroundDisplayMode: .never))
                    } else if page == pages.count {
                        zipPage
                            .padding(.horizontal, 26)
                    } else {
                        notificationsPage
                            .padding(.horizontal, 22)
                    }
                }
                .frame(maxHeight: .infinity)

                pageIndicator
                    .padding(.bottom, 18)

                bottomBar
                    .padding(.horizontal, 26)
                    .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.light)
    }

    // Now just 3 steps: intro → ZIP → notifications. Interests + factors
    // moved to inline personalization prompts that surface after the user
    // has seen their first real feed.
    private var totalPages: Int { pages.count + 2 }
    private var isZipPage: Bool { page == pages.count }
    private var isInterestsPage: Bool { false }
    private var isFactorsPage: Bool { false }
    private var isNotificationsPage: Bool { page == pages.count + 1 }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { idx in
                Capsule()
                    .fill(idx == page ? CivicTheme.ink : CivicTheme.hairline)
                    .frame(width: idx == page ? 28 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: page)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if page > 0 {
                Button {
                    Haptics.selection()
                    page = max(0, page - 1)
                } label: {
                    Text("Back")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                                .stroke(CivicTheme.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Button {
                Haptics.impact(.light)
                primaryAction()
            } label: {
                HStack {
                    Text(primaryButtonLabel)
                        .font(.system(size: 15, weight: .semibold))
                    if isZipPage && store.isResolvingProfile {
                        ProgressView().tint(.white)
                    } else if isFactorsPage {
                        Image(systemName: "checkmark")
                    } else {
                        Image(systemName: "arrow.right")
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(primaryButtonColor, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                .shadow(color: primaryButtonColor.opacity(0.30), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(primaryButtonDisabled)
        }
    }

    private func primaryAction() {
        if page < pages.count {
            page += 1
            if page == pages.count { zipFocused = true }
            return
        }
        if isZipPage {
            submitZip()
            return
        }
        if isInterestsPage {
            store.setInterests(selectedInterests)
            page += 1
            return
        }
        if isFactorsPage {
            store.setFactors(selectedFactors)
            page += 1
            return
        }
        // notifications page
        store.completeOnboarding()
    }

    private var primaryButtonLabel: String {
        if page < pages.count - 1 { return "Continue" }
        if page == pages.count - 1 { return "Set your ZIP" }
        if isZipPage {
            return store.isResolvingProfile ? "Looking up…" : "Find my reps"
        }
        if isInterestsPage {
            return selectedInterests.isEmpty ? "Skip for now" : "Continue"
        }
        if isFactorsPage {
            return selectedFactors.isEmpty ? "Continue" : "Continue"
        }
        if isNotificationsPage {
            return "Open the app"
        }
        return "Done"
    }

    private var primaryButtonColor: Color {
        if isZipPage && trimmedZip.count != 5 { return CivicTheme.quietInk }
        return CivicTheme.cyan
    }

    private var primaryButtonDisabled: Bool {
        if isZipPage {
            return trimmedZip.count != 5 || store.isResolvingProfile
        }
        return false
    }

    // MARK: - Notifications page

    private var notificationsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Vote reminders", systemImage: "bell.badge.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.amber)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text("Want a heads-up before your bookmarked items vote?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("We'll send a local notification 24 hours before, then again an hour before. No spam — only items you save or that match your interests.")
                    .font(.system(size: 13))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
            }

            VStack(spacing: 10) {
                Button {
                    Haptics.selection()
                    Task {
                        notificationsGranted = await CivicNotificationScheduler.shared.requestAuthorizationIfNeeded()
                        notificationsRequested = true
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: notificationsGranted ? "checkmark.circle.fill" : "bell.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(notificationsGranted ? "Notifications enabled" : "Yes, remind me")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(notificationsGranted ? CivicTheme.green : CivicTheme.amber, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                }
                .buttonStyle(.plain)
                .disabled(notificationsGranted)

                if notificationsRequested && !notificationsGranted {
                    Text("System notifications are off — you can turn them on later in iOS Settings → Athen.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var trimmedZip: String {
        zipDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 0)
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(page.tint.opacity(0.14))
                    .frame(width: 96, height: 96)
                Image(systemName: page.symbol)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(page.tint)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text(page.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(page.body)
                    .font(.system(size: 16))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var zipPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 14) {
                Label("Where do you live?", systemImage: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text("Your ZIP code finds your federal, state, and local representatives.")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Nothing else is collected. You can change it any time.")
                    .font(.system(size: 14))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
            }

            HStack(spacing: 10) {
                TextField("ZIP code", text: $zipDraft)
                    .textFieldStyle(.plain)
                    .keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(CivicTheme.ink)
                    .onChange(of: zipDraft) { _, newValue in
                        zipDraft = String(newValue.filter(\.isNumber).prefix(5))
                    }
                    .focused($zipFocused)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 18)
                    .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                            .stroke(CivicTheme.hairline, lineWidth: 1)
                    )
                    .shadow(color: CivicTheme.cardShadow, radius: 8, x: 0, y: 3)
            }

            if let err = store.profileError {
                Text(err)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CivicTheme.red)
            }

            Spacer(minLength: 0)
        }
    }

    private func submitZip() {
        Task {
            await store.updateZip(trimmedZip)
            if store.profile != nil {
                page += 1
            }
        }
    }

    // MARK: - Interests + factors pages

    private var interestsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label("What you care about", systemImage: "scope")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text("Pick the topics that matter to your household.")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Athen will rank items in your feed by these. You can change anytime from Radar → profile → Interests. Federal items always show.")
                    .font(.system(size: 13))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
            }
            ScrollView(showsIndicators: false) {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(CivicTopic.allCases) { topic in
                        topicPill(topic)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func topicPill(_ topic: CivicTopic) -> some View {
        let active = selectedInterests.contains(topic)
        return Button {
            Haptics.selection()
            if active { selectedInterests.remove(topic) } else { selectedInterests.insert(topic) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: topic.systemImage)
                    .font(.system(size: 12, weight: .bold))
                Text(topic.label)
                    .font(.system(size: 14, weight: .semibold))
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(active ? .white : topic.tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(active ? topic.tint : topic.tint.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(topic.tint.opacity(active ? 0 : 0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var factorsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Who you are", systemImage: "person.crop.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.violet)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text("Pick what describes you so we can show how each bill actually affects your household.")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Used for cohort projection on the Brief tab. Stays on your device.")
                    .font(.system(size: 13))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
            }
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(CivicProfileFactor.allCases) { factor in
                        factorRow(factor)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func factorRow(_ factor: CivicProfileFactor) -> some View {
        let active = selectedFactors.contains(factor)
        return Button {
            Haptics.selection()
            if active { selectedFactors.remove(factor) } else { selectedFactors.insert(factor) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(factor.tint.opacity(active ? 0.20 : 0.10))
                    Image(systemName: factor.systemImage)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(factor.tint)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(factor.label)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Text(factor.topics.map(\.label).sorted().joined(separator: " · "))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(active ? factor.tint : CivicTheme.quietInk)
            }
            .padding(12)
            .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(active ? factor.tint.opacity(0.30) : CivicTheme.hairline, lineWidth: active ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingPage {
    let symbol: String
    let tint: Color
    let title: String
    let body: String
}

#Preview {
    OnboardingView()
        .environment(CivicOSStore())
}
