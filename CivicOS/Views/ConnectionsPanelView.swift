import SwiftUI

/// You tab → Connected apps. Lists each Composio-supported integration with
/// connect / disconnect buttons. Connect opens the OAuth URL in an in-app
/// Safari sheet so the user's browser session can complete the flow without
/// leaving the app context.
struct ConnectionsPanelView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var oauthURL: SafariURL?
    @State private var pendingApp: String?
    @State private var inFlightError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        intro
                        if store.isLoadingIntegrations && store.integrationCatalog.isEmpty {
                            loadingCard
                        } else if store.integrationCatalog.isEmpty {
                            disabledCard
                        } else {
                            ForEach(store.integrationCatalog) { app in
                                connectionRow(app)
                            }
                        }
                        if let err = store.integrationsError ?? inFlightError {
                            errorBanner(err)
                        }
                        finePrint
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Connected apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.selection()
                        Task { await store.loadIntegrations() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CivicTheme.cyan)
                    }
                    .disabled(store.isLoadingIntegrations)
                }
            }
            .task { await store.loadIntegrations() }
            .sheet(item: $oauthURL, onDismiss: {
                // After the user closes the OAuth tab, re-check connection
                // status so the row flips to "Connected".
                Task { await store.loadIntegrations() }
            }) { item in
                SafariSheet(url: item.url)
                    .ignoresSafeArea()
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("INTEGRATIONS", systemImage: "link.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.violet)
                .tracking(0.5)
            Text("Hook up the tools you already use")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Powered by Composio. Connect Gmail to send filings from your own inbox, hook Calendar for vote countdowns, or post crew rallies to Slack. You can disconnect anytime.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(CivicTheme.violet)
            Text("Checking connections…")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private var disabledCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(CivicTheme.amber)
                Text("Integrations not configured")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
            }
            Text("Connected apps aren't available in this Athen build yet. Coming online when our integration partner is wired up.")
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.amber.opacity(0.20), lineWidth: 1))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CivicTheme.red)
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var finePrint: some View {
        Text("Athen never sees or stores your tokens. OAuth credentials live with Composio; we only ask for tightly scoped permissions per app.")
            .font(.system(size: 11))
            .foregroundStyle(CivicTheme.quietInk)
            .lineSpacing(2)
            .padding(.top, 6)
    }

    private func connectionRow(_ app: CivicIntegrationApp) -> some View {
        let status = store.integrationStatusByApp[app.appName]
        let isConnected = status?.isConnected == true
        let isWorking = pendingApp == app.appName
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(app.tint.opacity(0.15))
                    Image(systemName: app.systemImage)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(app.tint)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(app.displayName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        if isConnected {
                            Text("Connected")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(CivicTheme.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(CivicTheme.green.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(app.description)
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundStyle(CivicTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            }
            Button {
                Haptics.selection()
                if isConnected {
                    Task {
                        pendingApp = app.appName
                        await store.disconnectIntegration(app.appName)
                        pendingApp = nil
                    }
                } else {
                    Task {
                        pendingApp = app.appName
                        inFlightError = nil
                        do {
                            let url = try await store.connectIntegration(app.appName)
                            oauthURL = SafariURL(url: url)
                        } catch {
                            inFlightError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                        pendingApp = nil
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView().scaleEffect(0.7).tint(isConnected ? CivicTheme.red : .white)
                    } else {
                        Image(systemName: isConnected ? "minus.circle.fill" : "link.badge.plus")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(isConnected ? "Disconnect" : "Connect")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(isConnected ? CivicTheme.red : .white)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(isConnected ? CivicTheme.red.opacity(0.10) : app.tint, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isConnected ? CivicTheme.red.opacity(0.30) : Color.clear, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isWorking)

            // Once an app is connected, surface its automation toggles + targets.
            if isConnected {
                Divider().overlay(CivicTheme.hairline)
                automationControls(for: app.appName, tint: app.tint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    // MARK: - Per-app automations

    @ViewBuilder
    private func automationControls(for appName: String, tint: Color) -> some View {
        let bind = bindingForSettings
        VStack(alignment: .leading, spacing: 10) {
            Text("AUTOMATIONS")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(tint)
            switch appName {
            case "googlecalendar":
                Toggle("Add vote dates when I bookmark a bill", isOn: bind.calendarOnBookmark)
                    .font(.system(size: 13, weight: .semibold))
                    .tint(tint)
            case "notion":
                Toggle("Log every filing to my Notion DB", isOn: bind.notionOnFiling)
                    .font(.system(size: 13, weight: .semibold))
                    .tint(tint)
                Toggle("Log delivered petitions too", isOn: bind.notionOnPetition)
                    .font(.system(size: 13, weight: .semibold))
                    .tint(tint)
                automationField(label: "Notion database ID", text: bind.notionDatabaseId, placeholder: "Paste the database ID from the URL")
            case "slack":
                Toggle("Post group letters to Slack", isOn: bind.slackOnGroupLetter)
                    .font(.system(size: 13, weight: .semibold))
                    .tint(tint)
                Toggle("Post daily Brief to Slack", isOn: bind.slackOnDailyBrief)
                    .font(.system(size: 13, weight: .semibold))
                    .tint(tint)
                automationField(label: "Channel ID or #channel", text: bind.slackChannel, placeholder: "#civics")
            case "discord":
                Toggle("Cross-post group letters to Discord", isOn: bind.discordOnGroupLetter)
                    .font(.system(size: 13, weight: .semibold))
                    .tint(tint)
                Toggle("Post petition deliveries", isOn: bind.discordOnPetition)
                    .font(.system(size: 13, weight: .semibold))
                    .tint(tint)
                automationField(label: "Discord channel ID", text: bind.discordChannelId, placeholder: "Right-click channel → Copy ID")
            case "twitter":
                Toggle("Auto-post my filings to X", isOn: bind.twitterOnFiling)
                    .font(.system(size: 13, weight: .semibold))
                    .tint(tint)
                automationField(label: "Hashtags", text: bind.socialHashtags, placeholder: "civics athen")
            case "linkedin":
                Toggle("Auto-post my filings to LinkedIn", isOn: bind.linkedinOnFiling)
                    .font(.system(size: 13, weight: .semibold))
                    .tint(tint)
            case "gmail":
                Toggle("Email weekly civic digest to someone", isOn: bind.gmailDigestEnabled)
                    .font(.system(size: 13, weight: .semibold))
                    .tint(tint)
                automationField(label: "Recipient email", text: bind.gmailDigestRecipient, placeholder: "name@example.com")
            default:
                EmptyView()
            }
        }
    }

    private func automationField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(CivicTheme.quietInk)
            TextField(placeholder, text: text)
                .font(.system(size: 13))
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CivicTheme.hairline, lineWidth: 1))
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
    }

    /// Per-field bindings that read from / write to the store's settings.
    private var bindingForSettings: SettingsBindings {
        let s = store.integrationSettings
        return SettingsBindings(
            calendarOnBookmark: Binding(
                get: { s.calendarOnBookmark },
                set: { v in store.updateIntegrationSettings { $0.calendarOnBookmark = v } }
            ),
            notionOnFiling: Binding(
                get: { s.notionOnFiling },
                set: { v in store.updateIntegrationSettings { $0.notionOnFiling = v } }
            ),
            notionOnPetition: Binding(
                get: { s.notionOnPetition },
                set: { v in store.updateIntegrationSettings { $0.notionOnPetition = v } }
            ),
            notionDatabaseId: Binding(
                get: { s.notionDatabaseId },
                set: { v in store.updateIntegrationSettings { $0.notionDatabaseId = v } }
            ),
            slackOnGroupLetter: Binding(
                get: { s.slackOnGroupLetter },
                set: { v in store.updateIntegrationSettings { $0.slackOnGroupLetter = v } }
            ),
            slackOnDailyBrief: Binding(
                get: { s.slackOnDailyBrief },
                set: { v in store.updateIntegrationSettings { $0.slackOnDailyBrief = v } }
            ),
            slackChannel: Binding(
                get: { s.slackChannel },
                set: { v in store.updateIntegrationSettings { $0.slackChannel = v } }
            ),
            discordOnGroupLetter: Binding(
                get: { s.discordOnGroupLetter },
                set: { v in store.updateIntegrationSettings { $0.discordOnGroupLetter = v } }
            ),
            discordOnPetition: Binding(
                get: { s.discordOnPetition },
                set: { v in store.updateIntegrationSettings { $0.discordOnPetition = v } }
            ),
            discordChannelId: Binding(
                get: { s.discordChannelId },
                set: { v in store.updateIntegrationSettings { $0.discordChannelId = v } }
            ),
            twitterOnFiling: Binding(
                get: { s.twitterOnFiling },
                set: { v in store.updateIntegrationSettings { $0.twitterOnFiling = v } }
            ),
            linkedinOnFiling: Binding(
                get: { s.linkedinOnFiling },
                set: { v in store.updateIntegrationSettings { $0.linkedinOnFiling = v } }
            ),
            socialHashtags: Binding(
                get: { s.socialHashtags },
                set: { v in store.updateIntegrationSettings { $0.socialHashtags = v } }
            ),
            gmailDigestEnabled: Binding(
                get: { s.gmailDigestEnabled },
                set: { v in store.updateIntegrationSettings { $0.gmailDigestEnabled = v } }
            ),
            gmailDigestRecipient: Binding(
                get: { s.gmailDigestRecipient },
                set: { v in store.updateIntegrationSettings { $0.gmailDigestRecipient = v } }
            )
        )
    }
}

private struct SettingsBindings {
    let calendarOnBookmark: Binding<Bool>
    let notionOnFiling: Binding<Bool>
    let notionOnPetition: Binding<Bool>
    let notionDatabaseId: Binding<String>
    let slackOnGroupLetter: Binding<Bool>
    let slackOnDailyBrief: Binding<Bool>
    let slackChannel: Binding<String>
    let discordOnGroupLetter: Binding<Bool>
    let discordOnPetition: Binding<Bool>
    let discordChannelId: Binding<String>
    let twitterOnFiling: Binding<Bool>
    let linkedinOnFiling: Binding<Bool>
    let socialHashtags: Binding<String>
    let gmailDigestEnabled: Binding<Bool>
    let gmailDigestRecipient: Binding<String>
}

