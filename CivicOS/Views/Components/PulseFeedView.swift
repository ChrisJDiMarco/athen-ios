import SwiftUI

/// Unified live activity stream for the Pulse view mode. One chronological
/// feed instead of five stacked cards — bills, votes, social posts,
/// petitions, momentum signals, all mixed and ranked by recency.
///
/// Refreshes every 60s while visible. Pull-to-refresh hits the same path
/// as the rest of Home so the feed picks up newly-ingested bills.
struct PulseFeedView: View {
    @Environment(CivicOSStore.self) private var store
    let onSelectIssue: (UUID) -> Void

    @State private var scope: PulseScope = .all
    @State private var nowTick: Date = .now

    /// Ticks every 30s so relative timestamps stay fresh.
    private let nowTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            liveHeader
            scopeChips
            feed
        }
        .onReceive(nowTimer) { nowTick = $0 }
    }

    // MARK: - Header

    private var liveHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(CivicTheme.green.opacity(0.18))
                Circle().fill(CivicTheme.green).frame(width: 8, height: 8)
                    .modifier(PulsingDot())
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(CivicTheme.green)
                Text(headerSubtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
            }
            Spacer()
            Text("\(filteredEvents.count)")
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(CivicTheme.quietInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(CivicTheme.panelElevated, in: Capsule())
        }
    }

    private var headerSubtitle: String {
        let zip = store.profile?.zipCode
        let where_ = zip.map { "in \($0)" } ?? "in your area"
        return "What's happening \(where_) right now"
    }

    // MARK: - Filter chips

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PulseScope.allCases) { s in
                    chip(s)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func chip(_ s: PulseScope) -> some View {
        let isActive = scope == s
        return Button {
            Haptics.selection()
            scope = s
        } label: {
            HStack(spacing: 6) {
                Image(systemName: s.systemImage)
                    .font(.system(size: 10, weight: .bold))
                Text(s.label)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(isActive ? .white : CivicTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isActive ? CivicTheme.violet : CivicTheme.panelElevated, in: Capsule())
            .overlay(Capsule().stroke(isActive ? CivicTheme.violet : CivicTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feed

    @ViewBuilder
    private var feed: some View {
        if filteredEvents.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                ForEach(filteredEvents) { event in
                    eventRow(event)
                    if event.id != filteredEvents.last?.id {
                        Divider()
                            .background(CivicTheme.hairline)
                            .padding(.leading, 56)
                    }
                }
            }
            .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
        }
    }

    private func eventRow(_ event: PulseEvent) -> some View {
        Button {
            Haptics.selection()
            if let id = event.issueID {
                onSelectIssue(id)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(event.tint.opacity(0.14))
                    Image(systemName: event.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(event.tint)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(event.categoryLabel)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(event.tint)
                        Text("·")
                            .foregroundStyle(CivicTheme.quietInk)
                        Text(relative(event.timestamp))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CivicTheme.quietInk)
                            .id(nowTick) // re-renders when timer ticks
                    }
                    Text(event.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CivicTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !event.subtitle.isEmpty {
                        Text(event.subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                if event.issueID != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CivicTheme.quietInk)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(event.issueID == nil)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk.opacity(0.5))
            Text("All quiet")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("New activity will appear here as it happens — bills, votes, neighbors taking action.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CivicTheme.mutedInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    // MARK: - Event building

    /// Single source of truth: build a ranked unified feed from local stores.
    /// Kept @MainActor-safe by reading off the store directly.
    private var filteredEvents: [PulseEvent] {
        let all = buildEvents()
        let scoped = all.filter { matches(event: $0, scope: scope) }
        return scoped
            .sorted { lhs, rhs in
                if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
                return lhs.timestamp > rhs.timestamp
            }
            .prefix(40)
            .map { $0 }
    }

    private func matches(event: PulseEvent, scope: PulseScope) -> Bool {
        switch scope {
        case PulseScope.all:
            return true
        case PulseScope.mine:
            guard let id = event.issueID, let issue = store.issue(with: id) else { return false }
            guard let zip = store.profile?.zipCode else { return true }
            // Bills with a matching ZIP, or whose jurisdiction string
            // mentions it. ZIP-3 prefix match catches city-wide bills
            // tagged to a representative ZIP in the same district.
            let zip3 = String(zip.prefix(3))
            return issue.zipCode == zip
                || issue.zipCode.hasPrefix(zip3)
                || issue.jurisdiction.contains(zip)
        case PulseScope.federal:
            guard let id = event.issueID, let issue = store.issue(with: id) else { return false }
            if case .federal = issue.scope { return true } else { return false }
        case PulseScope.state:
            guard let id = event.issueID, let issue = store.issue(with: id) else { return false }
            if case .state = issue.scope { return true } else { return false }
        case PulseScope.local:
            guard let id = event.issueID, let issue = store.issue(with: id) else { return false }
            if case .localPhilly = issue.scope { return true } else { return false }
        }
    }

    private func buildEvents() -> [PulseEvent] {
        var out: [PulseEvent] = []
        let now = Date.now

        // 1) Imminent votes (highest priority)
        for issue in store.issues where issue.voteDate > now {
            let hoursOut = issue.voteDate.timeIntervalSince(now) / 3600
            if hoursOut < 48 {
                out.append(PulseEvent(
                    id: "vote-imm-\(issue.id.uuidString)",
                    kind: .voteImminent,
                    timestamp: now,
                    title: issue.title,
                    subtitle: "Vote in \(humanize(hours: hoursOut)) · \(issue.jurisdiction)",
                    issueID: issue.id,
                    weight: 100 - hoursOut // sooner = higher
                ))
            } else if hoursOut < 24 * 14 {
                out.append(PulseEvent(
                    id: "vote-\(issue.id.uuidString)",
                    kind: .voteScheduled,
                    timestamp: issue.voteDate.addingTimeInterval(-hoursOut * 3600),
                    title: issue.title,
                    subtitle: "Vote scheduled \(relative(issue.voteDate)) · \(issue.jurisdiction)",
                    issueID: issue.id,
                    weight: 50 - hoursOut / 24
                ))
            }
        }

        // 2) Recent diff events (status changes)
        for diff in store.diffEvents.prefix(15) {
            let age = now.timeIntervalSince(diff.detectedAt) / 3600
            let headline = (diff.plainEnglish?.isEmpty == false) ? diff.plainEnglish! : diff.kind.label
            out.append(PulseEvent(
                id: "diff-\(diff.id.uuidString)",
                kind: .diffChange,
                timestamp: diff.detectedAt,
                title: diff.issueTitle,
                subtitle: headline,
                issueID: diff.issueID,
                weight: max(40 - age, 5)
            ))
        }

        // 3) Petition milestones (10/50/100/500/1000)
        for petition in store.petitions {
            if let milestone = milestoneHit(count: petition.signerCount) {
                out.append(PulseEvent(
                    id: "petition-\(petition.id)-\(milestone)",
                    kind: .petitionMilestone,
                    timestamp: petition.createdAt,
                    title: petition.title,
                    subtitle: "\(petition.signerCount) signers · hit \(milestone)",
                    issueID: nil,
                    weight: Double(milestone) / 50
                ))
            }
        }

        // 4) Recent Square posts (filed kind only — those are real civic moves)
        for post in store.socialPosts.prefix(15) where post.kind == .filed {
            let age = now.timeIntervalSince(post.createdAt) / 3600
            guard age < 24 * 7 else { continue }
            out.append(PulseEvent(
                id: "post-\(post.id.uuidString)",
                kind: .squarePost,
                timestamp: post.createdAt,
                title: post.body,
                subtitle: "\(post.authorName) · \(post.locality)",
                issueID: post.issueID,
                weight: max(30 - age, 3)
            ))
        }

        // 5) Recent bills (introduced) — modest weight, fall in last
        let recentIssues = store.issues
            .sorted { $0.voteDate > $1.voteDate }
            .prefix(20)
        for issue in recentIssues {
            let voteAge = abs(now.timeIntervalSince(issue.voteDate)) / 3600 / 24
            guard voteAge < 30 else { continue }
            // Avoid double-counting items already added as voteImminent / voteScheduled
            if out.contains(where: { $0.issueID == issue.id }) { continue }
            out.append(PulseEvent(
                id: "bill-\(issue.id.uuidString)",
                kind: .billIntroduced,
                timestamp: issue.voteDate,
                title: issue.title,
                subtitle: "\(issue.jurisdiction) · \(issue.sourceName)",
                issueID: issue.id,
                weight: 20 - voteAge / 2
            ))
        }

        return out
    }

    private func milestoneHit(count: Int) -> Int? {
        let tiers = [1000, 500, 100, 50, 10]
        return tiers.first { count >= $0 }
    }

    // MARK: - Helpers

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: nowTick)
    }

    private func humanize(hours: Double) -> String {
        if hours < 1 { return "\(Int(hours * 60))m" }
        if hours < 24 { return "\(Int(hours))h" }
        return "\(Int(hours / 24))d"
    }
}
