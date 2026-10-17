import SwiftUI

/// Full-screen reader view for one Claude-generated brief.
/// Tap any deep-brief card → this opens with all sections expanded:
/// key facts, two sides, fiscal impact, timeline, every cohort projection,
/// pull quote, recommended action, and quick handoffs to chat / share / file.
struct BriefDetailView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: CivicBriefDigestItem

    @State private var selectedAudience: BriefAudience?
    @State private var rewriteText: String?
    @State private var rewriteError: String?
    @State private var isRewriting: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    metadataStrip
                    if let brief = brief {
                        hero(brief)
                        leadSection(brief)
                        if !brief.keyFacts.isEmpty { keyFactsSection(brief) }
                        if !brief.twoSides.isEmpty { sidesSection(brief) }
                        fiscalSection(brief)
                        explainForMeSection
                        if !brief.timeline.isEmpty { timelineSection(brief) }
                        if !brief.cohortProjections.isEmpty { cohortsSection(brief) }
                        if let quote = brief.pullQuote, !quote.isEmpty { pullQuoteSection(quote) }
                        nextStepSection(brief)
                        actionRow(brief)
                        sourceFooter(brief)
                    } else {
                        pendingState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(CivicTheme.screenBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                        .font(.system(size: 15, weight: .semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if brief == nil && store.generatingBriefFor.contains(item.issueId) {
                        ProgressView().scaleEffect(0.8)
                    } else if brief == nil {
                        Button {
                            Haptics.selection()
                            Task { await store.generateBrief(for: item.issueId) }
                        } label: {
                            Label("Generate", systemImage: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CivicTheme.violet)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var brief: CivicBriefAnalysis? {
        store.brief(for: item.issueId) ?? item.brief
    }

    // MARK: - Sections

    private var metadataStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: scopeIcon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(scopeTint)
            Text(item.issue.scope.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(scopeTint)
                .tracking(0.4)
            Text("·")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
            Text(item.issue.jurisdiction)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let trust = item.issue.trustScore {
                Text("\(trust)% trust")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CivicTheme.green.opacity(0.12), in: Capsule())
            }
        }
    }

    private func hero(_ brief: CivicBriefAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                AIDisclosureChip(surface: .brief)
                Spacer()
                ConfidenceChip(label: brief.confidence.label)
            }
            Text(brief.headline)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(brief.subhead)
                .font(.system(size: 15, weight: .semibold))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                ReadAloudButton(text: { briefReadAloudScript(brief) }, label: "Read this brief")
                Spacer()
            }
            .padding(.top, 2)
        }
    }

    private func briefReadAloudScript(_ brief: CivicBriefAnalysis) -> String {
        var parts: [String] = [brief.headline, brief.subhead, brief.lead]
        if !brief.keyFacts.isEmpty {
            parts.append("Key facts.")
            parts.append(brief.keyFacts.prefix(5).map { "\($0.label): \($0.value)." }.joined(separator: " "))
        }
        if !brief.twoSides.isEmpty {
            parts.append("Both sides.")
            parts.append(brief.twoSides.prefix(2).map { "\($0.stance.label). \($0.headline). \($0.argument)" }.joined(separator: " "))
        }
        if !brief.fiscalImpact.isEmpty {
            parts.append("Fiscal impact. \(brief.fiscalImpact)")
        }
        return parts.joined(separator: " ")
    }

    private func leadSection(_ brief: CivicBriefAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("The story", systemImage: "text.book.closed.fill", tint: CivicTheme.cyan)
            Text(brief.lead)
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func keyFactsSection(_ brief: CivicBriefAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Key facts", systemImage: "list.bullet.rectangle.fill", tint: CivicTheme.cyan)
            VStack(spacing: 10) {
                ForEach(brief.keyFacts) { fact in
                    DetailKeyFactRow(fact: fact)
                }
            }
        }
    }

    private func sidesSection(_ brief: CivicBriefAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Both sides", systemImage: "scale.3d", tint: CivicTheme.violet)
            VStack(spacing: 10) {
                ForEach(brief.twoSides) { side in
                    DetailSideRow(side: side)
                }
            }
        }
    }

    private func fiscalSection(_ brief: CivicBriefAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Fiscal impact", systemImage: "dollarsign.circle.fill", tint: CivicTheme.green)
            Text(brief.fiscalImpact)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CivicTheme.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.green.opacity(0.20), lineWidth: 1))
        }
    }

    private var explainForMeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Explain it for…", systemImage: "person.crop.circle.badge.questionmark", tint: CivicTheme.violet)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BriefAudience.allCases) { audience in
                        audiencePill(audience)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()

            if isRewriting {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Rewriting for \(selectedAudience?.pillLabel ?? "…")…")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 12))
            } else if let text = rewriteText, let audience = selectedAudience {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: audience.systemImage)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CivicTheme.violet)
                        Text(audience.pillLabel.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(CivicTheme.violet)
                        Spacer()
                        Button {
                            Haptics.selection()
                            rewriteText = nil
                            selectedAudience = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(CivicTheme.quietInk)
                                .padding(4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss rewrite")
                    }
                    Text(text)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundStyle(CivicTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CivicTheme.violet.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.violet.opacity(0.20), lineWidth: 1))
            } else if let err = rewriteError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.amber)
                    Text(err)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CivicTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func audiencePill(_ audience: BriefAudience) -> some View {
        let active = selectedAudience == audience
        return Button {
            Haptics.selection()
            requestRewrite(for: audience)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: audience.systemImage)
                    .font(.system(size: 11, weight: .bold))
                Text(audience.pillLabel)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(active ? .white : CivicTheme.violet)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(active ? CivicTheme.violet : CivicTheme.violet.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(CivicTheme.violet.opacity(active ? 0 : 0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isRewriting)
    }

    private func requestRewrite(for audience: BriefAudience) {
        selectedAudience = audience
        rewriteText = nil
        rewriteError = nil
        isRewriting = true
        Task {
            do {
                let text = try await store.rewriteBrief(for: item.issueId, audience: audience)
                await MainActor.run {
                    rewriteText = text
                    isRewriting = false
                }
            } catch {
                await MainActor.run {
                    rewriteError = (error as? CivicFilingError)?.localizedDescription ?? error.localizedDescription
                    isRewriting = false
                }
            }
        }
    }

    private func timelineSection(_ brief: CivicBriefAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Timeline", systemImage: "calendar.badge.clock", tint: CivicTheme.amber)
            VStack(spacing: 10) {
                ForEach(brief.timeline) { entry in
                    TimelineRow(entry: entry)
                }
            }
        }
    }

    private func cohortsSection(_ brief: CivicBriefAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("How this affects different people", systemImage: "person.3.fill", tint: CivicTheme.violet)
            VStack(spacing: 10) {
                ForEach(brief.cohortProjections) { projection in
                    CohortRow(projection: projection)
                }
            }
        }
    }

    private func pullQuoteSection(_ quote: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle().fill(CivicTheme.violet).frame(width: 4).cornerRadius(2)
            Text("\u{201C}\(quote)\u{201D}")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .italic()
                .lineSpacing(4)
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func nextStepSection(_ brief: CivicBriefAnalysis) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CivicTheme.violet)
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(CivicTheme.violet)
                Text(brief.recommendedAction)
                    .font(.system(size: 15, weight: .semibold))
                    .lineSpacing(3)
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.violet.opacity(0.20), lineWidth: 1))
    }

    private func actionRow(_ brief: CivicBriefAnalysis) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                actionButton(title: "Ask Athen", systemImage: "bubble.left.fill", tint: CivicTheme.cyan) {
                    store.queueAssistantPrompt("Explain \(item.issue.title) like I'm a neighbor with no time. Use this brief: \(brief.headline). \(brief.subhead) \(brief.lead)")
                    dismiss()
                }
                ShareLink(item: shareText(brief)) {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .bold))
                        Text("Share")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(CivicTheme.mutedInk)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
                }
                .simultaneousGesture(TapGesture().onEnded { Haptics.selection() })
            }
            Button {
                Haptics.selection()
                // Brief is shown as a sheet (no NavigationStack destination
                // for UUID is registered here), so we route through the
                // global deep-link path that MainTabView listens on and
                // dismiss this sheet so the issue can present cleanly.
                guard let id = UUID(uuidString: item.issueId),
                      store.issue(with: id) != nil else { return }
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    store.pendingDeepLinkIssueID = id
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Open the underlying issue")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(CivicTheme.violet, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: CivicTheme.violet.opacity(0.25), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.20), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func sourceFooter(_ brief: CivicBriefAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source attribution")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
                .textCase(.uppercase)
                .tracking(0.4)
            Text(brief.sourceLine)
                .font(.system(size: 12))
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("Generated by Athen · \(brief.model) · \(relativeLabel(brief.generatedAt))")
                .font(.system(size: 11))
                .foregroundStyle(CivicTheme.quietInk)
        }
    }

    private var pendingState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.issue.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.issue.summary)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.selection()
                Task { await store.generateBrief(for: item.issueId) }
            } label: {
                HStack(spacing: 8) {
                    if store.generatingBriefFor.contains(item.issueId) {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(store.generatingBriefFor.contains(item.issueId) ? "Athen is thinking…" : "Generate AI brief")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(CivicTheme.violet, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(store.generatingBriefFor.contains(item.issueId))
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(tint)
            Rectangle()
                .fill(tint.opacity(0.25))
                .frame(height: 1)
        }
    }

    private var scopeIcon: String {
        switch item.issue.scope {
        case "federal": "building.columns.fill"
        case "state": "flag.fill"
        case "local-philly": "building.2.fill"
        default: "globe.americas.fill"
        }
    }

    private var scopeTint: Color {
        switch item.issue.scope {
        case "federal": CivicTheme.cyan
        case "state": CivicTheme.violet
        case "local-philly": CivicTheme.amber
        default: CivicTheme.mutedInk
        }
    }

    private func relativeLabel(_ date: Date) -> String {
        let interval = -date.timeIntervalSinceNow
        switch interval {
        case ..<60: return "just now"
        case ..<3600: return "\(max(1, Int(interval / 60)))m ago"
        case ..<86400: return "\(max(1, Int(interval / 3600)))h ago"
        default: return "\(max(1, Int(interval / 86400)))d ago"
        }
    }

    private func shareText(_ brief: CivicBriefAnalysis) -> String {
        """
        \(brief.headline)

        \(brief.subhead)

        \(brief.lead)

        Next step: \(brief.recommendedAction)

        Via Athen — athen://issue/\(item.issueId)
        """
    }
}

private struct ConfidenceChip: View {
    let label: CivicBriefAnalysis.Confidence.Label

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(label.tint).frame(width: 6, height: 6)
            Text(label.display)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(label.tint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(label.tint.opacity(0.10), in: Capsule())
    }
}

private struct DetailKeyFactRow: View {
    let fact: CivicBriefAnalysis.KeyFact

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(fact.label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(CivicTheme.cyan)
            Text(fact.value)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DetailSideRow: View {
    let side: CivicBriefAnalysis.Side

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: side.stance.systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(side.stance.tint)
                    .frame(width: 24, height: 24)
                    .background(side.stance.tint.opacity(0.14), in: Circle())
                Text(side.stance.label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(side.stance.tint)
                Text("·")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
                Text(side.who)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            Text(side.headline)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(side.argument)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(side.stance.tint.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(side.stance.tint.opacity(0.18), lineWidth: 1))
    }
}

private struct TimelineRow: View {
    let entry: CivicBriefAnalysis.TimelineEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .stroke(CivicTheme.amber, lineWidth: 1.8)
                    .frame(width: 12, height: 12)
                    .padding(.top, 4)
                Rectangle()
                    .fill(CivicTheme.amber.opacity(0.25))
                    .frame(width: 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(displayDate)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(CivicTheme.amber)
                    .textCase(.uppercase)
                Text(entry.label)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var displayDate: String {
        guard let date = entry.date else { return entry.dateISO }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private struct CohortRow: View {
    let projection: CivicBriefAnalysis.CohortProjection

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: projection.cohort.systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(projection.cohort.tint)
                .frame(width: 28, height: 28)
                .background(projection.cohort.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(projection.cohort.label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(projection.cohort.tint)
                Text(projection.impact)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(projection.cohort.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(projection.cohort.tint.opacity(0.18), lineWidth: 1))
    }
}
