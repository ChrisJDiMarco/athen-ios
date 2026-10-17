import SwiftUI

struct FeaturedImpactCard: View {
    @Environment(CivicOSStore.self) private var store
    let issue: CivicIssue

    var body: some View {
        CivicGlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 8) {
                    RectBadge(
                        text: issue.impactLevel.rawValue,
                        systemImage: issue.impactLevel.symbolName,
                        tint: CivicTheme.impactColor(for: issue.impactLevel)
                    )

                    RectBadge(
                        text: issue.voteCountdownLabel,
                        systemImage: "calendar.badge.clock",
                        tint: CivicTheme.impactColor(for: issue.urgencyTint)
                    )

                    Spacer()

                    FilingStateBadge(status: store.status(for: issue))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(issue.title)
                        .font(.system(size: 29, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(issue.summary)
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .foregroundStyle(CivicTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    MiniFact(
                        label: "Vote",
                        value: issue.voteDate.formatted(date: .abbreviated, time: .shortened),
                        tint: CivicTheme.amber
                    )

                    MiniFact(
                        label: "Route",
                        value: issue.official.district,
                        tint: CivicTheme.cyan
                    )
                }
            }
        }
    }
}

struct CompactImpactCard: View {
    @Environment(CivicOSStore.self) private var store
    let issue: CivicIssue

    var body: some View {
        CivicGlassCard(padding: 13) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: issue.impactLevel.symbolName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CivicTheme.impactColor(for: issue.impactLevel))

                    Spacer()

                    FilingStateIcon(status: store.status(for: issue))
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(issue.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.86)

                    Text(issue.category)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.quietInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CivicTheme.impactColor(for: issue.urgencyTint))
                    Text(issue.voteCountdownLabel)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.impactColor(for: issue.urgencyTint))
                }
            }
            .frame(minHeight: 142, alignment: .top)
        }
    }
}

private struct MiniFact: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(12)
        .background(CivicTheme.panelElevated)
        .clipShape(RoundedRectangle(cornerRadius: CivicTheme.mediumRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius, style: .continuous)
                .stroke(CivicTheme.hairline, lineWidth: 1)
        )
    }
}

private struct FilingStateBadge: View {
    let status: FilingStatus

    var body: some View {
        switch status {
        case .ready:
            RectBadge(text: "Ready", systemImage: "paperplane", tint: CivicTheme.cyan)
        case let .drafting(action):
            RectBadge(text: "Drafting \(action.rawValue)", systemImage: "sparkles", tint: CivicTheme.violet)
        case let .sending(action):
            RectBadge(text: "Sending \(action.rawValue)", systemImage: "arrow.triangle.2.circlepath", tint: CivicTheme.amber)
        case .sent:
            RectBadge(text: "Sent", systemImage: "checkmark.circle.fill", tint: CivicTheme.green)
        case .failed:
            RectBadge(text: "Retry", systemImage: "exclamationmark.circle.fill", tint: CivicTheme.red)
        }
    }
}

private struct FilingStateIcon: View {
    let status: FilingStatus

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(tint)
    }

    private var iconName: String {
        switch status {
        case .ready:
            "paperplane"
        case .drafting:
            "sparkles"
        case .sending:
            "arrow.triangle.2.circlepath"
        case .sent:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.circle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .ready:
            CivicTheme.cyan
        case .drafting:
            CivicTheme.violet
        case .sending:
            CivicTheme.amber
        case .sent:
            CivicTheme.green
        case .failed:
            CivicTheme.red
        }
    }
}
