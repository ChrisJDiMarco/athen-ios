import SwiftUI

struct ActionBarView: View {
    @Environment(CivicOSStore.self) private var store
    let issue: CivicIssue

    @State private var pendingAction: CivicAction?
    @State private var safariURL: SafariURL?
    /// Tally fetched from /v1/issues/:id/tally — { endorseCount, opposeCount }.
    /// Local-only optimistic increment after this user's send so the count
    /// updates instantly without waiting for the next backend roundtrip.
    @State private var tally: IssueFilingTally?
    /// Briefly shown after a tap so the user gets instant confirmation
    /// that their position was counted, even before the draft sheet opens
    /// (or if drafting fails because no official is reachable).
    @State private var positionRecordedAction: CivicAction?

    private var status: FilingStatus {
        store.status(for: issue)
    }

    private var isRegulatory: Bool {
        JurisdictionScope.isRegulatory(jurisdiction: issue.jurisdiction, scope: issue.scope)
    }

    var body: some View {
        VStack(spacing: 10) {
            // Social proof — how many other Athen users have weighed in.
            if let tally, (tally.endorseCount + tally.opposeCount) > 0 {
                tallyStrip(tally)
            }

            if let positionRecordedAction {
                positionRecordedToast(action: positionRecordedAction)
            }

            if isRegulatory {
                regulatoryAction
            } else {
                switch status {
                case .ready, .failed:
                    actionButtons
                case let .drafting(action):
                    draftingState(action: action)
                case let .sending(action):
                    sendingState(action: action)
                case let .sent(receipt):
                    sentState(receipt: receipt)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(CivicTheme.panel)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(CivicTheme.hairline)
                .frame(height: 1)
        }
        .sheet(item: $pendingAction) { action in
            DraftFilingSheet(issue: issue, action: action, positionAlreadyRecorded: true)
                .environment(store)
        }
        .sheet(item: $safariURL) { wrapper in
            SafariSheet(url: wrapper.url)
                .ignoresSafeArea()
        }
        .task(id: issue.id) {
            tally = await store.loadFilingTally(issueId: issue.id.uuidString)
        }
        .onChange(of: status) { _, new in
            // Optimistically bump the tally locally the moment this user's
            // filing flips to "sent" — the backend has the canonical count
            // but we don't want to wait for the next /tally call.
            guard case let .sent(receipt) = new else { return }
            if receipt.action == .endorse {
                tally = (tally ?? IssueFilingTally(endorseCount: 0, opposeCount: 0))
                    .incrementingEndorse()
            } else if receipt.action == .oppose {
                tally = (tally ?? IssueFilingTally(endorseCount: 0, opposeCount: 0))
                    .incrementingOppose()
            }
        }
    }

    /// Record the user's stance with the backend (bumps the public tally
    /// without requiring address resolution or email delivery), then open
    /// the draft sheet for the optional email follow-on. Decoupling the
    /// two means a federal-agency rule or ZIP-only state issue still
    /// counts the user's position even if no official is reachable.
    private func handleActionTap(_ action: CivicAction) {
        Haptics.impact(.light)

        // 1) Optimistic local bump so the tally strip moves instantly.
        let base = tally ?? IssueFilingTally(endorseCount: 0, opposeCount: 0)
        tally = action == .endorse ? base.incrementingEndorse() : base.incrementingOppose()

        // 2) Flash the "Position recorded" toast for ~1.6s as instant proof.
        positionRecordedAction = action
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if positionRecordedAction == action { positionRecordedAction = nil }
        }

        // 3) Fire the backend record (canonical tally update). Replace the
        //    local optimistic value if the server returns something different.
        Task {
            if let updated = await store.recordPosition(
                issueId: issue.id.uuidString,
                action: action
            ) {
                tally = updated
            }
        }

        // 4) For non-regulatory items, also open the draft sheet so the
        //    user can send a personal email if their official is reachable.
        if !isRegulatory {
            pendingAction = action
        }
    }

    private func tallyStrip(_ tally: IssueFilingTally) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.thumbsup.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.green)
            Text("\(tally.endorseCount) endorsed")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("·")
                .foregroundStyle(CivicTheme.quietInk)
            Image(systemName: "hand.thumbsdown.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.red)
            Text("\(tally.opposeCount) opposed")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Spacer()
            Text("Athen users")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CivicTheme.quietInk)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(CivicTheme.panelElevated, in: Capsule())
        .overlay(Capsule().stroke(CivicTheme.hairline, lineWidth: 1))
    }

    /// Federal-agency / regulatory items aren't filable by email — the real
    /// channel is a public comment on Regulations.gov / Federal Register.
    /// Show Endorse/Oppose buttons (position-record only — no email draft)
    /// PLUS a CTA to open the source for the formal comment submission.
    private var regulatoryAction: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                CivicActionButton(
                    title: "Endorse",
                    systemImage: CivicAction.endorse.systemImage,
                    tint: CivicTheme.green
                ) {
                    handleActionTap(.endorse)
                }

                CivicActionButton(
                    title: "Oppose",
                    systemImage: CivicAction.oppose.systemImage,
                    tint: CivicTheme.red
                ) {
                    handleActionTap(.oppose)
                }
            }

            Button {
                Haptics.impact(.light)
                if let raw = issue.sourceURL, let url = URL(string: raw) {
                    safariURL = SafariURL(url: url)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Submit a public comment")
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(CivicTheme.violet, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                .shadow(color: CivicTheme.violet.opacity(0.18), radius: 5, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(issue.sourceURL == nil)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            CivicActionButton(
                title: "Endorse",
                systemImage: CivicAction.endorse.systemImage,
                tint: CivicTheme.green
            ) {
                handleActionTap(.endorse)
            }

            CivicActionButton(
                title: "Oppose",
                systemImage: CivicAction.oppose.systemImage,
                tint: CivicTheme.red
            ) {
                handleActionTap(.oppose)
            }
        }
    }

    private func positionRecordedToast(action: CivicAction) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(action == .endorse ? CivicTheme.green : CivicTheme.red)
            Text("Position recorded — \(action == .endorse ? "Endorse" : "Oppose") counted")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            (action == .endorse ? CivicTheme.green : CivicTheme.red).opacity(0.10),
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(
                (action == .endorse ? CivicTheme.green : CivicTheme.red).opacity(0.30),
                lineWidth: 1
            )
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func draftingState(action: CivicAction) -> some View {
        HStack(spacing: 12) {
            ProgressView().tint(CivicTheme.violet)
            Text("Drafting \(action.rawValue.lowercased()) message…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CivicTheme.ink)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(CivicTheme.violet.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: CivicTheme.mediumRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius, style: .continuous)
                .stroke(CivicTheme.violet.opacity(0.30), lineWidth: 1)
        }
    }

    private func sendingState(action: CivicAction) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(CivicTheme.amber)

            Text("Filing \(action.rawValue.lowercased()) with \(issue.official.name)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CivicTheme.ink)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(CivicTheme.amber.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: CivicTheme.mediumRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius, style: .continuous)
                .stroke(CivicTheme.amber.opacity(0.30), lineWidth: 1)
        }
    }

    private func sentState(receipt: FilingReceipt) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CivicTheme.green)

            VStack(alignment: .leading, spacing: 3) {
                Text("Sent to \(receipt.officialName)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text("Confirmation \(receipt.confirmationCode)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(CivicTheme.green.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: CivicTheme.mediumRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius, style: .continuous)
                .stroke(CivicTheme.green.opacity(0.30), lineWidth: 1)
        }
    }
}

/// Banner above the Endorse/Oppose buttons that sets honest expectations
/// about what tapping Send will actually do. Without this, the user invests
/// 5 minutes drafting then sees "Recorded in your history" and feels duped.
struct FilingDeliveryBanner: View {
    let isGmailConnected: Bool
    let onLearnMore: () -> Void

    var body: some View {
        if isGmailConnected {
            connectedBanner
        } else {
            recordedLocalBanner
        }
    }

    private var connectedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text("Position counts + Gmail sends")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text("Your stance is tallied; the email goes from your inbox.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CivicTheme.green)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
        }
    }

    private var recordedLocalBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text("Position always counts")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text("Connect Gmail to also send a direct email")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
            Spacer(minLength: 0)
            Button(action: onLearnMore) {
                Text("How")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CivicTheme.cyan)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
        }
    }
}

private struct CivicActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))

                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: CivicTheme.mediumRadius, style: .continuous))
            .shadow(color: tint.opacity(0.30), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Files a formal constituent message")
    }
}
