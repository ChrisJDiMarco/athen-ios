import SwiftUI

/// State-specific voter registration walkthrough. Pulls the state's portal
/// URL, registration features, deadline, and ID requirements from the
/// backend's static state table. One-tap opens the official portal in an
/// in-app Safari sheet.
struct VoterRegistrationView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var portalURL: SafariURL?

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        intro
                        if let reg = store.registrationInfo {
                            stateHero(reg)
                            featureGrid(reg)
                            deadlineCard(reg)
                            idRequirementsCard(reg)
                            portalButton(reg)
                            if let notes = reg.notes {
                                notesCard(notes)
                            }
                            fineprint
                        } else if store.profile == nil {
                            zipPromptCard
                        } else if store.isLoadingVoterRail {
                            loadingCard
                        } else {
                            errorCard
                        }
                        Color.clear.frame(height: 30)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
            }
            .navigationTitle("Register to vote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
            .task {
                if store.registrationInfo == nil {
                    await store.loadVoterRail()
                }
            }
            .sheet(item: $portalURL) { url in
                SafariSheet(url: url.url)
                    .ignoresSafeArea()
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("VOTER REGISTRATION", systemImage: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(CivicTheme.amber)
            Text("Register or check your status")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Athen opens your state's official registration portal. We never collect your registration data — it's between you and your state.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stateHero(_ reg: StateRegistrationInfo) -> some View {
        HStack(spacing: 14) {
            Text(reg.stateCode)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(CivicTheme.amber, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(reg.stateName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text(reg.deadlineLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
            }
            Spacer()
        }
    }

    private func featureGrid(_ reg: StateRegistrationInfo) -> some View {
        HStack(spacing: 8) {
            featureChip("Online registration", isOn: reg.online, systemImage: "globe", tint: CivicTheme.cyan)
            featureChip("Same-day", isOn: reg.sameDay, systemImage: "clock.fill", tint: CivicTheme.green)
            featureChip("Auto at DMV", isOn: reg.automaticAtDMV, systemImage: "car.fill", tint: CivicTheme.violet)
        }
    }

    private func featureChip(_ label: String, isOn: Bool, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: isOn ? systemImage : "minus.circle")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isOn ? tint : CivicTheme.quietInk)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isOn ? CivicTheme.ink : CivicTheme.quietInk)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(8)
        .background(isOn ? tint.opacity(0.08) : CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isOn ? tint.opacity(0.20) : CivicTheme.hairline, lineWidth: 1))
    }

    private func deadlineCard(_ reg: StateRegistrationInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CivicTheme.red)
                .frame(width: 40, height: 40)
                .background(CivicTheme.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("REGISTRATION DEADLINE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(CivicTheme.red)
                Text(reg.deadlineLabel)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func idRequirementsCard(_ reg: StateRegistrationInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ID AT THE POLLS")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(CivicTheme.violet)
            Text(reg.idRequirements)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.violet.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.violet.opacity(0.18), lineWidth: 1))
    }

    private func portalButton(_ reg: StateRegistrationInfo) -> some View {
        Button {
            Haptics.selection()
            if let url = URL(string: reg.portalURL) { portalURL = SafariURL(url: url) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: reg.online ? "globe.americas.fill" : "doc.text.fill")
                    .font(.system(size: 16, weight: .bold))
                Text(reg.online ? "Open \(reg.stateName) registration portal" : "Get \(reg.stateName) registration info")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(CivicTheme.amber, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: CivicTheme.amber.opacity(0.30), radius: 12, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }

    private func notesCard(_ notes: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(CivicTheme.cyan)
            Text(notes)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.cyan.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var fineprint: some View {
        Text("Source: state secretary of state offices, last verified 2026. Confirm on the linked portal for the most current per-election cutoff.")
            .font(.system(size: 11))
            .foregroundStyle(CivicTheme.quietInk)
            .lineSpacing(2)
            .padding(.top, 8)
    }

    private var zipPromptCard: some View {
        Text("Set your ZIP from Radar → profile so we can pull your state's registration rules.")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(CivicTheme.mutedInk)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CivicTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(CivicTheme.amber)
            Text("Looking up your state's rules…")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private var errorCard: some View {
        Text(store.lastVoterRailError ?? "Couldn't load registration info.")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(CivicTheme.red)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CivicTheme.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
