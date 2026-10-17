import SwiftUI

struct CivicActionPlanCard: View {
    @Environment(CivicOSStore.self) private var store
    let issue: CivicIssue
    let onOpenRally: () -> Void

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    SectionHeader(title: "Action plan", systemImage: "checklist.checked")
                    Spacer()
                    RectBadge(
                        text: insight.recommendedAction,
                        systemImage: insight.priority.systemImage,
                        tint: insight.priority.tint
                    )
                }

                Text(bestMove)
                    .font(.system(size: 15, weight: .medium))
                    .lineSpacing(3)
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 0) {
                    TimelineStepRow(
                        title: "Know why it matters",
                        detail: insight.reason,
                        state: .complete,
                        isLast: false
                    )
                    TimelineStepRow(
                        title: fileStepTitle,
                        detail: fileStepDetail,
                        state: fileStepState,
                        isLast: false
                    )
                    TimelineStepRow(
                        title: "Create pressure",
                        detail: crewStepDetail,
                        state: rallyCount == 0 ? .pending : .complete,
                        isLast: false
                    )
                    TimelineStepRow(
                        title: "Follow up",
                        detail: followUpDetail,
                        state: followUpState,
                        isLast: true
                    )
                }

                HStack(spacing: 9) {
                    Button {
                        Haptics.selection()
                        store.queueAssistantPrompt(
                            issue.assistantActionPlanPrompt(
                                profile: store.profile,
                                alreadySent: status.isSent,
                                rallyCount: rallyCount
                            )
                        )
                    } label: {
                        PlanControlLabel(title: "Ask AI", systemImage: "sparkles", tint: CivicTheme.violet)
                    }
                    .buttonStyle(.plain)

                    ShareLink(item: shareText) {
                        PlanControlLabel(title: "Share", systemImage: "square.and.arrow.up", tint: CivicTheme.cyan)
                    }

                    Button {
                        Haptics.selection()
                        store.queueSocialComposer(for: issue)
                    } label: {
                        PlanControlLabel(title: "Post", systemImage: "plus.bubble.fill", tint: CivicTheme.amber)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.selection()
                        onOpenRally()
                    } label: {
                        PlanControlLabel(title: "Outreach", systemImage: "person.3.fill", tint: CivicTheme.green)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var status: FilingStatus {
        store.status(for: issue)
    }

    private var insight: CivicRadarInsight {
        store.radarInsight(for: issue)
    }

    private var rallyCount: Int {
        store.rallyCount(for: issue)
    }

    private var bestMove: String {
        if store.profile == nil {
            return "Set your ZIP first so \(AppBrand.name) can verify the right officials, then use the action bar below to file."
        }
        if status.isSent {
            return "You already filed. The best next move is to rally a few people and watch for the official reply or outcome."
        }
        if issue.hasVotePassed {
            return "The action window has closed. Save the item, check the official source, and ask the assistant for follow-up paths."
        }
        if issue.hoursUntilVote <= 24 {
            return "This is inside the short window. File your position now, then send a concise nudge to your crew."
        }
        if store.groups.isEmpty {
            return "Review the facts, file if you have a position, then create a crew so next time you are not acting alone."
        }
        return "File your position, then open outreach while the issue is still fresh."
    }

    private var fileStepTitle: String {
        switch status {
        case .sent: "Filing complete"
        case .drafting: "Draft in progress"
        case .sending: "Filing in progress"
        case .failed: "Retry filing"
        case .ready: "File your position"
        }
    }

    private var fileStepDetail: String {
        switch status {
        case let .sent(receipt):
            return "\(receipt.action.rawValue) sent to \(receipt.officialName)"
        case let .drafting(action):
            return "Drafting a \(action.rawValue.lowercased()) message for review"
        case let .sending(action):
            return "Sending your \(action.rawValue.lowercased()) message to \(issue.official.name)"
        case let .failed(message):
            return message
        case .ready:
            return issue.hasVotePassed ? "Window closed. Use AI to plan follow-up." : "Use Endorse or Oppose below after reviewing the facts."
        }
    }

    private var fileStepState: TimelineStepState {
        switch status {
        case .sent: .complete
        case .drafting, .sending: .active
        case .failed: .warning
        case .ready: issue.hasVotePassed ? .muted : .pending
        }
    }

    private var crewStepDetail: String {
        if store.groups.isEmpty {
            return "No crew yet. Start one from profile, or share this issue directly."
        }
        if rallyCount == 0 {
            return "\(store.groups.count) crew\(store.groups.count == 1 ? "" : "s") ready. No one has been nudged yet."
        }
        return "\(rallyCount) person\(rallyCount == 1 ? "" : "s") marked as rallied on this issue."
    }

    private var followUpDetail: String {
        if status.isSent {
            return issue.hasVotePassed ? "Check the outcome and compare it with your position." : "Watch for a reply before \(issue.voteCountdownLabel)."
        }
        if issue.hasVotePassed {
            return "Watch for the outcome, then ask the assistant what changed."
        }
        return "After filing, track the reply, vote result, and whether your crew engaged."
    }

    private var followUpState: TimelineStepState {
        if status.isSent { return .active }
        return issue.hasVotePassed ? .active : .pending
    }

    private var shareText: String {
        let link = issue.sourceURL ?? "athen://issue/\(issue.id.uuidString)"
        return "\(AppBrand.name) flagged this: \(issue.title). \(issue.summary) \(link)"
    }
}

struct IssueTimelineCard: View {
    let issue: CivicIssue
    let status: FilingStatus
    let rallyCount: Int

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Issue timeline", systemImage: "point.3.connected.trianglepath.dotted")

                VStack(alignment: .leading, spacing: 0) {
                    TimelineStepRow(
                        title: "Source detected",
                        detail: issue.sourceName,
                        state: .complete,
                        isLast: false
                    )
                    TimelineStepRow(
                        title: "Translated",
                        detail: "\(issue.facts.count) facts · \(issue.citations.count) citations · \(issue.trustLabel)",
                        state: .complete,
                        isLast: false
                    )
                    TimelineStepRow(
                        title: issue.hasVotePassed ? "Action window closed" : "Action window",
                        detail: issue.timingSummary,
                        state: issue.hasVotePassed ? .muted : .active,
                        isLast: false
                    )
                    TimelineStepRow(
                        title: filingTitle,
                        detail: filingDetail,
                        state: filingState,
                        isLast: false
                    )
                    TimelineStepRow(
                        title: "Crew signal",
                        detail: rallyCount == 0 ? "No one rallied yet" : "\(rallyCount) person\(rallyCount == 1 ? "" : "s") rallied on this issue",
                        state: rallyCount == 0 ? .pending : .complete,
                        isLast: true
                    )
                }
            }
        }
    }

    private var filingTitle: String {
        switch status {
        case .sent: "Filed"
        case .drafting: "Drafting"
        case .sending: "Sending"
        case .failed: "Needs retry"
        case .ready: "Ready to file"
        }
    }

    private var filingDetail: String {
        switch status {
        case let .sent(receipt):
            return "\(receipt.action.rawValue) sent to \(receipt.officialName)"
        case let .drafting(action):
            return "AI is drafting your \(action.rawValue.lowercased()) message"
        case let .sending(action):
            return "Filing \(action.rawValue.lowercased()) with \(issue.official.name)"
        case let .failed(message):
            return message
        case .ready:
            return "Choose Endorse or Oppose when ready"
        }
    }

    private var filingState: TimelineStepState {
        switch status {
        case .sent: .complete
        case .drafting, .sending: .active
        case .failed: .warning
        case .ready: .pending
        }
    }
}

struct RallyCrewCard: View {
    let issue: CivicIssue
    let groupCount: Int
    let memberCount: Int
    let rallyCount: Int
    let onOpen: () -> Void

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    SectionHeader(title: "Rally your crew", systemImage: "person.3.fill")
                    Spacer()
                    RectBadge(
                        text: rallyCount == 0 ? "Not started" : "\(rallyCount) rallied",
                        systemImage: rallyCount == 0 ? "paperplane" : "checkmark.circle.fill",
                        tint: rallyCount == 0 ? CivicTheme.amber : CivicTheme.green
                    )
                }

                Text(summary)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onOpen) {
                    HStack(spacing: 10) {
                        Image(systemName: groupCount == 0 ? "person.crop.circle.badge.plus" : "paperplane.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(groupCount == 0 ? "Set up a crew" : "Open outreach")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 14)
                    .background(CivicTheme.violet, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                    .shadow(color: CivicTheme.violet.opacity(0.24), radius: 7, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var summary: String {
        if groupCount == 0 {
            return "One filing is a signal. A handful of neighbors filing before \(issue.voteCountdownLabel) is leverage. Create a crew in You, then come back here."
        }
        return "\(memberCount) member\(memberCount == 1 ? "" : "s") across \(groupCount) crew\(groupCount == 1 ? "" : "s"). Send issue-specific texts and track who you've nudged."
    }
}

struct RallyCrewSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let issue: CivicIssue

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if store.groups.isEmpty {
                            emptyCrewState
                        } else {
                            ForEach(store.groups) { group in
                                RallyGroupSection(issue: issue, group: group)
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outreach")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text(issue.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Send a short, issue-specific nudge. Mark people as rallied so the timeline reflects real outreach.")
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
        }
    }

    private var emptyCrewState: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("No crew yet", systemImage: "person.crop.circle.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.amber)
                Text("Create a crew from profile. Add the neighbors, family, or group chat people you'd actually text about a vote.")
                    .font(.system(size: 14))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
            }
        }
    }
}

private struct RallyGroupSection: View {
    @Environment(CivicOSStore.self) private var store
    let issue: CivicIssue
    let group: OutreachGroup

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(group.emoji)
                        .font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        Text("\(group.members.count) member\(group.members.count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                    }
                    Spacer()
                }

                if group.members.isEmpty {
                    Text("No members yet. Add people from the crew detail screen.")
                        .font(.system(size: 13))
                        .foregroundStyle(CivicTheme.mutedInk)
                } else {
                    VStack(spacing: 8) {
                        ForEach(group.members) { member in
                            RallyMemberRow(
                                issue: issue,
                                groupID: group.id,
                                member: member,
                                hasRallied: store.memberHasRallied(member.id, in: group.id, for: issue)
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct RallyMemberRow: View {
    @Environment(CivicOSStore.self) private var store
    let issue: CivicIssue
    let groupID: OutreachGroup.ID
    let member: GroupMember
    let hasRallied: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(CivicTheme.cyan.opacity(0.13))
                Text(member.emoji)
                    .font(.system(size: 18))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(member.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
                Text(hasRallied ? "Rallied on this issue" : member.phoneOrHandle ?? "Ready to nudge")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hasRallied ? CivicTheme.green : CivicTheme.mutedInk)
                    .lineLimit(1)
            }

            Spacer()

            ShareLink(item: outreachText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
                    .frame(width: 34, height: 34)
                    .background(CivicTheme.cyan.opacity(0.11), in: Circle())
            }

            Button {
                Haptics.success()
                store.logRally(memberID: member.id, groupID: groupID, issue: issue)
            } label: {
                Image(systemName: hasRallied ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(hasRallied ? CivicTheme.green : CivicTheme.quietInk)
            }
            .buttonStyle(.plain)
            .disabled(hasRallied)
        }
        .padding(12)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                .stroke(hasRallied ? CivicTheme.green.opacity(0.25) : CivicTheme.hairline, lineWidth: 1)
        )
    }

    private var outreachText: String {
        let link = "athen://issue/\(issue.id.uuidString)"
        return "Hey \(member.name) — there's a vote/comment window on \(issue.title). \(issue.personalReason(for: store.profile)) \(AppBrand.name) summarizes it and lets you file in about 30 seconds: \(link)"
    }
}

private struct PlanControlLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }
}

private enum TimelineStepState {
    case complete
    case active
    case pending
    case warning
    case muted

    var tint: Color {
        switch self {
        case .complete: CivicTheme.green
        case .active: CivicTheme.cyan
        case .pending: CivicTheme.quietInk
        case .warning: CivicTheme.red
        case .muted: CivicTheme.mutedInk
        }
    }

    var icon: String {
        switch self {
        case .complete: "checkmark"
        case .active: "arrow.right"
        case .pending: "circle"
        case .warning: "exclamationmark"
        case .muted: "minus"
        }
    }
}

private struct TimelineStepRow: View {
    let title: String
    let detail: String
    let state: TimelineStepState
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(state.tint.opacity(0.15))
                    Image(systemName: state.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(state.tint)
                }
                .frame(width: 26, height: 26)

                if !isLast {
                    Rectangle()
                        .fill(CivicTheme.hairline)
                        .frame(width: 1, height: 34)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text(detail)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 12)
        }
    }
}
