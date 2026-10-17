import SwiftUI

struct DraftFilingSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let issue: CivicIssue
    let action: CivicAction
    /// When true (the default after the position-first refactor), the
    /// failure view reframes "draft didn't go through" into a friendly
    /// "position recorded; we couldn't reach an official for the email"
    /// message instead of an alarming error. Old call sites can pass
    /// false to keep the legacy hard-error UI.
    var positionAlreadyRecorded: Bool = false

    @State private var draft: DraftedFiling?
    @State private var subjectDraft: String = ""
    @State private var bodyDraft: String = ""
    @State private var errorMessage: String?
    @State private var phase: Phase = .loading
    @State private var selectedToneKey: String? = nil
    @State private var defaultSubject: String = ""
    @State private var defaultBody: String = ""
    @FocusState private var bodyFocused: Bool

    enum Phase: Equatable {
        case loading
        case ready
        case sending
        case queued(deadline: Date)
        case sent(FilingReceipt)
        case failed
    }

    private static let undoWindowSeconds: Double = 5

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()

                Group {
                    switch phase {
                    case .loading, .ready, .sending:
                        // Render the structural shell IMMEDIATELY — the body
                        // area shows an inline loading state while Claude
                        // generates. No fullscreen blocker.
                        readyView
                    case .failed:
                        if draft == nil { failedView } else { readyView }
                    case let .queued(deadline): queuedView(deadline: deadline)
                    case let .sent(receipt): sentView(receipt: receipt)
                    }
                }
            }
            .navigationTitle("Review your filing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        Haptics.selection()
                        dismiss()
                    }
                    .foregroundStyle(CivicTheme.cyan)
                    .disabled(phase == .sending || isQueuedPhase)
                }
            }
        }
        .task { await loadDraft() }
        .interactiveDismissDisabled(phase == .sending || isQueuedPhase)
    }

    private var isQueuedPhase: Bool {
        if case .queued = phase { return true }
        return false
    }

    // MARK: - Views

    /// Heuristic: if the backend told us no official could be reached
    /// (federal-agency rule, ZIP-only state issue, unmapped local
    /// jurisdiction), the user's position is still recorded — we just
    /// can't draft a direct email. Frame it as success-with-limit, not
    /// failure.
    private var isNoOfficialError: Bool {
        guard let msg = errorMessage?.lowercased() else { return false }
        let signals = [
            "no filing official",
            "regulatory_no_filing_official",
            "no official",
            "no_official",
            "state_legislators_unavailable",
            "not in philadelphia council districts",
            "couldn't find your representative",
        ]
        return signals.contains { msg.contains($0) }
    }

    @ViewBuilder
    private var failedView: some View {
        if positionAlreadyRecorded && isNoOfficialError {
            positionRecordedFailureView
        } else {
            legacyFailedView
        }
    }

    /// Friendly version for the position-first flow when we can't reach
    /// an official directly. The user's stance is already counted in the
    /// public tally — this view explains the email half didn't happen
    /// and offers Share to Square as the next-best amplifier.
    private var positionRecordedFailureView: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill((action == .endorse ? CivicTheme.green : CivicTheme.red).opacity(0.14))
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(action == .endorse ? CivicTheme.green : CivicTheme.red)
            }
            .frame(width: 76, height: 76)

            VStack(spacing: 8) {
                Text("Your \(action == .endorse ? "endorse" : "oppose") is counted")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text("Athen couldn't draft a direct email for this item — federal-agency rules and some state issues don't map to a single contactable office. Your position is in the public tally and your filing history.")
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(CivicTheme.mutedInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
            }

            if let raw = issue.sourceURL, let _ = URL(string: raw) {
                Text("For federal rules, formal comments go through Regulations.gov — tap below to open the source.")
                    .font(.system(size: 11))
                    .foregroundStyle(CivicTheme.quietInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 10) {
                Button {
                    Haptics.impact(.light)
                    let body = "I just \(action == .endorse ? "endorsed" : "opposed") \(issue.title). Athen counted my position."
                    store.createSocialPost(kind: .filed, body: body, issueID: issue.id, imageData: nil)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("Share on Square")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(CivicTheme.cyan, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.selection()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CivicTheme.mutedInk)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var legacyFailedView: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(CivicTheme.amber.opacity(0.14))
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(CivicTheme.amber)
            }
            .frame(width: 72, height: 72)
            VStack(spacing: 8) {
                Text(positionAlreadyRecorded ? "Email didn't go through" : "Draft didn't go through")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                if positionAlreadyRecorded {
                    Text("Your position is recorded. We hit a snag drafting the email — retry below or tap Done.")
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(CivicTheme.mutedInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                } else {
                    Text(errorMessage ?? "Something went wrong while drafting your message.")
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(CivicTheme.mutedInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                }
            }
            VStack(spacing: 10) {
                Button(action: retryDraft) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(CivicTheme.violet, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                Button {
                    Haptics.selection()
                    dismiss()
                } label: {
                    Text(positionAlreadyRecorded ? "Done" : "Cancel")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CivicTheme.mutedInk)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isDrafting: Bool { draft == nil && phase == .loading }

    private var readyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                actionBanner

                CivicGlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Filing with", systemImage: "person.text.rectangle.fill")
                        if let draft {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.official.name)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(CivicTheme.ink)
                                Text(draft.official.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(CivicTheme.mutedInk)
                                Text(draft.verifiedAddress)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(CivicTheme.quietInk)
                            }
                            channelBadge(for: draft.official.channel)
                            if store.isGmailConnected, draft.official.channel == .email {
                                gmailToggle
                            }
                            automationPreview
                        } else {
                            officialSkeleton
                        }
                    }
                }

                toneSelectorCard

                CivicGlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Subject", systemImage: "envelope.fill")
                        ZStack(alignment: .leading) {
                            TextField("", text: $subjectDraft, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(CivicTheme.ink)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 14)
                                .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                                .overlay(
                                    RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                                        .stroke(CivicTheme.hairline, lineWidth: 1)
                                )
                                .disabled(isDrafting)
                                .opacity(isDrafting ? 0 : 1)
                            if isDrafting {
                                subjectSkeleton
                            }
                        }
                    }
                }

                CivicGlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionHeader(title: "Message", systemImage: "text.quote")
                            Spacer()
                            if isDrafting {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.mini).tint(CivicTheme.violet)
                                    Text("Drafting")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(CivicTheme.violet)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(CivicTheme.violet.opacity(0.12), in: Capsule())
                            } else {
                                Text("Editable")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(CivicTheme.violet)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(CivicTheme.violet.opacity(0.12), in: Capsule())
                            }
                        }
                        ZStack {
                            TextEditor(text: $bodyDraft)
                                .scrollContentBackground(.hidden)
                                .focused($bodyFocused)
                                .font(.system(size: 15))
                                .foregroundStyle(CivicTheme.ink)
                                .frame(minHeight: 220)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                                .overlay(
                                    RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                                        .stroke(CivicTheme.hairline, lineWidth: 1)
                                )
                                .disabled(isDrafting)
                                .opacity(isDrafting ? 0 : 1)
                            if isDrafting {
                                bodyDraftingOverlay
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CivicTheme.red)
                }

                sendButton
                    .disabled(isDrafting)
                    .opacity(isDrafting ? 0.55 : 1)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private var officialSkeleton: some View {
        VStack(alignment: .leading, spacing: 8) {
            shimmerBlock(width: 200, height: 16)
            shimmerBlock(width: 140, height: 12)
            shimmerBlock(width: 180, height: 11)
        }
        .padding(.vertical, 2)
    }

    private var subjectSkeleton: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.mini).tint(CivicTheme.cyan)
            Text("Composing subject line…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CivicTheme.mutedInk)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                .stroke(CivicTheme.hairline, lineWidth: 1)
        )
    }

    private var bodyDraftingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView().tint(CivicTheme.violet)
            Text("Athen is writing your \(action.rawValue.lowercased()) message…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CivicTheme.mutedInk)
                .multilineTextAlignment(.center)
            Text("Personalizing it with your ZIP, profile, and the bill's text.")
                .font(.system(size: 11))
                .foregroundStyle(CivicTheme.quietInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                .stroke(CivicTheme.hairline, lineWidth: 1)
        )
    }

    private func shimmerBlock(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(CivicTheme.hairline.opacity(0.6))
            .frame(width: width, height: height)
            .overlay(
                LinearGradient(
                    colors: [.clear, CivicTheme.panel.opacity(0.6), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
            )
    }

    private var actionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: action.systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(action == .endorse ? CivicTheme.green : CivicTheme.red)
            Text("Filing as \(action == .endorse ? "ENDORSE" : "OPPOSE")")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(action == .endorse ? CivicTheme.green : CivicTheme.red)
                .tracking(0.8)
            Spacer()
            Text(issue.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background((action == .endorse ? CivicTheme.green : CivicTheme.red).opacity(0.10), in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                .stroke((action == .endorse ? CivicTheme.green : CivicTheme.red).opacity(0.25), lineWidth: 1)
        )
    }

    private var sendButton: some View {
        Button(action: send) {
            HStack {
                if phase == .sending {
                    ProgressView().tint(.white)
                    Text("Sending…")
                        .font(.system(size: 15, weight: .semibold))
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Send")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(CivicTheme.cyan, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
            .shadow(color: CivicTheme.cyan.opacity(0.25), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(phase == .sending || draft == nil || bodyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var gmailToggle: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CivicTheme.red)
                .frame(width: 28, height: 28)
                .background(CivicTheme.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("Send from my Gmail")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text("Replies route to your inbox, not Athen's.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { store.isGmailFilingEnabled },
                set: { store.setGmailFilingEnabled($0) }
            ))
            .labelsHidden()
            .tint(CivicTheme.red)
        }
        .padding(10)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var automationPreview: some View {
        let connected = store.connectedAppNames
        let s = store.integrationSettings
        let willLogNotion = s.notionOnFiling && connected.contains("notion") && !s.notionDatabaseId.isEmpty
        let willPostX = s.twitterOnFiling && connected.contains("twitter")
        let willPostLinkedIn = s.linkedinOnFiling && connected.contains("linkedin")
        if willLogNotion || willPostX || willPostLinkedIn {
            VStack(alignment: .leading, spacing: 4) {
                Text("WHEN SENT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(CivicTheme.violet)
                HStack(spacing: 6) {
                    if willLogNotion {
                        automationChip(label: "Log to Notion", systemImage: "doc.text.fill", tint: CivicTheme.ink)
                    }
                    if willPostX {
                        automationChip(label: "Post to X", systemImage: "bird.fill", tint: CivicTheme.cyan)
                    }
                    if willPostLinkedIn {
                        automationChip(label: "Post to LinkedIn", systemImage: "briefcase.fill", tint: CivicTheme.cyan)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CivicTheme.violet.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.violet.opacity(0.16), lineWidth: 1))
        }
    }

    private func automationChip(label: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CivicTheme.green)
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.10), in: Capsule())
    }

    @ViewBuilder
    private func channelBadge(for channel: FilingChannel) -> some View {
        switch channel {
        case .email:
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CivicTheme.green)
                Text("Direct email — delivered within minutes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CivicTheme.green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(CivicTheme.green.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(CivicTheme.green.opacity(0.25), lineWidth: 1))
        case .contactFormQueue:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.up.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.amber)
                    Text("Submitted to public contact form (queued)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.amber)
                }
                Text("Federal offices accept submissions through their public forms, not direct email. We queue your message and submit it within the next hour.")
                    .font(.system(size: 11))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(CivicTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: CivicTheme.smallRadius))
            .overlay(
                RoundedRectangle(cornerRadius: CivicTheme.smallRadius)
                    .stroke(CivicTheme.amber.opacity(0.25), lineWidth: 1)
            )
        case .recordedLocal:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.cyan)
                    Text("Recorded in your history")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.cyan)
                }
                Text("Athen is in public beta. Your stance, your rep's name, the draft body and timestamp are saved to your filing history. Direct delivery to officials' offices is rolling out in a later release — connect your Gmail in Settings to enable it sooner.")
                    .font(.system(size: 11))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(CivicTheme.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: CivicTheme.smallRadius))
            .overlay(
                RoundedRectangle(cornerRadius: CivicTheme.smallRadius)
                    .stroke(CivicTheme.cyan.opacity(0.25), lineWidth: 1)
            )
        }
    }

    @State private var didShareToSquare = false
    @State private var shareSquareNote: String = ""

    private func sentView(receipt: FilingReceipt) -> some View {
        let isLocalOnly = receipt.channel == .recordedLocal
        let icon = isLocalOnly ? "tray.full.fill" : (receipt.queued ? "tray.and.arrow.up.fill" : "checkmark.seal.fill")
        let tint = isLocalOnly ? CivicTheme.cyan : (receipt.queued ? CivicTheme.amber : CivicTheme.green)
        let title = isLocalOnly ? "Recorded" : (receipt.queued ? "Queued" : "Filed")
        let subtitle = isLocalOnly ? "Saved to your stance with \(receipt.officialName)" : "Sent to \(receipt.officialName)"

        return ScrollView {
            VStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(tint)
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .multilineTextAlignment(.center)
                }
                if !receipt.statusNote.isEmpty {
                    Text(receipt.statusNote)
                        .font(.system(size: 13))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(receipt.confirmationCode)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(tint.opacity(0.12), in: Capsule())

                squareShareCard

                Button {
                    Haptics.selection()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(CivicTheme.cyan, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                        .shadow(color: CivicTheme.cyan.opacity(0.25), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        }
    }

    @ViewBuilder
    private var squareShareCard: some View {
        if didShareToSquare {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(CivicTheme.green)
                Text("Posted to Square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.green)
            }
            .padding(.vertical, 8)
        } else {
            CivicGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(CivicTheme.cyan)
                        Text("SHARE TO SQUARE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CivicTheme.cyan)
                            .tracking(0.5)
                        Spacer()
                    }
                    Text("Tell your crew you filed. Your neighbors can co-sign and I'm-in to pile on.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineSpacing(2)
                    TextField(defaultShareNote, text: $shareSquareNote, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(CivicTheme.ink)
                        .padding(10)
                        .frame(minHeight: 64, alignment: .topLeading)
                        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 10))
                    Button {
                        Haptics.selection()
                        let body = shareSquareNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? defaultShareNote
                            : shareSquareNote
                        store.createSocialPost(kind: .filed, body: body, issueID: issue.id, imageData: nil)
                        didShareToSquare = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Post to Square")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(CivicTheme.cyan, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var defaultShareNote: String {
        let verb = action == .endorse ? "Endorsed" : "Opposed"
        return "\(verb) \(issue.title). Took about a minute through Athen."
    }

    // MARK: - Actions

    private func loadDraft() async {
        Haptics.impact(.light)
        // Variants are nice-to-have; never let them block or break the base draft.
        async let toneTask: Void = store.loadDraftVariants(for: action, issue: issue)
        let result = await store.beginDraft(action, for: issue)
        await toneTask
        if let result, !result.message.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.draft = result
            self.subjectDraft = result.message.subject
            self.bodyDraft = result.message.body
            self.defaultSubject = result.message.subject
            self.defaultBody = result.message.body
            self.phase = .ready
            // Smart-default tone: only swap if the variant actually has a non-empty body.
            // Stops a misbehaving variants endpoint from clobbering the working draft.
            if let key = suggestedToneKey(),
               let match = availableVariants.first(where: { $0.key == key }),
               !match.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                applyTone(key: key)
            }
            Haptics.impact(.medium)
        } else {
            // Surface the real reason from the store instead of a generic message.
            // The user needs to know if it's a backend / ZIP / Claude issue so they
            // can fix it instead of guessing.
            self.errorMessage = currentStoreFailureMessage()
            self.phase = .failed
            Haptics.error()
        }
    }

    private func currentStoreFailureMessage() -> String {
        if case let .failed(message) = store.status(for: issue), !message.isEmpty {
            return message
        }
        if store.profile == nil {
            return "Set your ZIP from Radar → profile first — we need it to find your representative."
        }
        if store.backendStatus.shortLabel == "Offline" {
            return "Backend is offline. Check Radar → profile → AI backend and try again."
        }
        return "Couldn't draft your message. Tap Retry to try again."
    }

    private func retryDraft() {
        // Clear any stale failed status so beginDraft will proceed.
        store.clearFilingFailure(for: issue)
        errorMessage = nil
        phase = .loading
        Task { await loadDraft() }
    }

    private func suggestedToneKey() -> String? {
        guard let factors = store.profile?.factors, !factors.isEmpty else { return nil }
        let issueTopics = issue.topics
        // Prefer the user's factor whose interest topics overlap the issue's
        // topics — that's the one most relevant to this specific item.
        let ranked = factors.sorted { a, b in
            let aOverlap = a.topics.intersection(issueTopics).count
            let bOverlap = b.topics.intersection(issueTopics).count
            if aOverlap != bOverlap { return aOverlap > bOverlap }
            return a.rawValue < b.rawValue
        }
        for factor in ranked {
            switch factor {
            case .parent: return "parent"
            case .renter: return "renter"
            case .businessOwner: return "businessOwner"
            case .homeowner, .commuter, .accessibilityNeeds, .climateFlood: continue
            }
        }
        return nil
    }

    // MARK: - Tone selector

    private var availableVariants: [DraftToneVariant] {
        store.draftVariants[issue.id] ?? []
    }

    private var isLoadingVariants: Bool {
        store.generatingVariantsFor.contains(issue.id)
    }

    @ViewBuilder
    private var toneSelectorCard: some View {
        if isLoadingVariants || !availableVariants.isEmpty {
            CivicGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        SectionHeader(title: "Voice", systemImage: "person.wave.2.fill")
                        Spacer()
                        if isLoadingVariants {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Drafting voices…")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CivicTheme.mutedInk)
                            }
                        }
                    }
                    Text("Tap a voice to swap the message in your own style. The default is a balanced constituent voice.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineSpacing(2)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            tonePill(
                                key: nil,
                                label: "Default",
                                description: "Original Claude draft",
                                systemImage: "sparkles",
                                tint: CivicTheme.violet
                            )
                            ForEach(availableVariants) { variant in
                                tonePill(
                                    key: variant.key,
                                    label: variant.label,
                                    description: variant.description,
                                    systemImage: variant.systemImage,
                                    tint: variant.tint
                                )
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
            }
        }
    }

    private func tonePill(
        key: String?,
        label: String,
        description _: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        let isActive = selectedToneKey == key
        return Button {
            Haptics.selection()
            applyTone(key: key)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(isActive ? .white : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isActive ? tint : tint.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(isActive ? 0 : 0.20), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func applyTone(key: String?) {
        selectedToneKey = key
        if let key, let match = availableVariants.first(where: { $0.key == key }) {
            subjectDraft = match.subject
            bodyDraft = match.body
        } else {
            subjectDraft = defaultSubject
            bodyDraft = defaultBody
        }
        Haptics.impact(.light)
    }

    private func send() {
        guard var draft = draft else { return }
        draft.message = DraftedFilingMessage(
            subject: subjectDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            body: bodyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        self.draft = draft
        errorMessage = nil
        bodyFocused = false
        Haptics.impact(.medium)

        // Queue the send with an undo window. The store fires the actual
        // confirmSend after the window expires unless we cancel first.
        let handle = store.queueSend(draft, undoWindowSeconds: Self.undoWindowSeconds)
        phase = .queued(deadline: handle.expiresAt)

        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.undoWindowSeconds * 1_000_000_000))
            // Window elapsed. If still queued in our local phase, the store
            // already fired confirmSend — read back the final status.
            guard isQueuedPhase else { return }
            // Brief grace period for confirmSend to settle the receipt.
            try? await Task.sleep(nanoseconds: 250_000_000)
            let final = store.status(for: issue)
            if case let .sent(receipt) = final {
                phase = .sent(receipt)
                Haptics.success()
            } else if case let .failed(message) = final {
                errorMessage = message
                phase = .failed
                Haptics.error()
            } else {
                phase = .ready
            }
        }
    }

    private func undoQueuedSend() {
        Haptics.selection()
        store.cancelPendingSend(issue.id)
        phase = .ready
    }

    private func queuedView(deadline: Date) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(CivicTheme.cyan.opacity(0.14))
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
            }
            .frame(width: 76, height: 76)

            VStack(spacing: 6) {
                Text("Sending in a moment")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text("Tap undo and we'll cancel before it leaves.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .multilineTextAlignment(.center)
            }

            CountdownPill(deadline: deadline)

            Button(action: undoQueuedSend) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .bold))
                    Text("Undo")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(CivicTheme.amber, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                .shadow(color: CivicTheme.amber.opacity(0.25), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CountdownPill: View {
    let deadline: Date
    @State private var remaining: Int = 0

    var body: some View {
        Text("\(max(0, remaining))s")
            .font(.system(size: 16, weight: .bold, design: .monospaced))
            .foregroundStyle(CivicTheme.amber)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(CivicTheme.amber.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(CivicTheme.amber.opacity(0.30), lineWidth: 1))
            .onAppear { tick() }
            .task(id: deadline) {
                while !Task.isCancelled {
                    tick()
                    if remaining <= 0 { break }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
    }

    private func tick() {
        remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
    }
}
