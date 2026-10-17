import SwiftUI

struct CivicRadarHeroCard: View {
    let insight: CivicRadarInsight
    let readyCount: Int
    let dueSoonCount: Int
    let followUpCount: Int

    var body: some View {
        CivicGlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    RectBadge(
                        text: insight.priority.label,
                        systemImage: insight.priority.systemImage,
                        tint: insight.priority.tint
                    )
                    RectBadge(
                        text: insight.issue.voteCountdownLabel,
                        systemImage: "calendar.badge.clock",
                        tint: CivicTheme.impactColor(for: insight.issue.urgencyTint)
                    )
                    Spacer()
                    Text("\(insight.score)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(insight.priority.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(insight.priority.tint.opacity(0.12), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your civic radar")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.quietInk)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(insight.issue.title)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(insight.reason)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    RadarMiniMetric(value: "\(readyCount)", label: "Ready", tint: CivicTheme.cyan)
                    RadarMiniMetric(value: "\(dueSoonCount)", label: "Soon", tint: CivicTheme.amber)
                    RadarMiniMetric(value: "\(followUpCount)", label: "Follow", tint: CivicTheme.green)
                }

                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(insight.priority.tint)
                    Text(insight.recommendedAction)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CivicTheme.quietInk)
                }
                .padding(13)
                .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                        .stroke(CivicTheme.hairline, lineWidth: 1)
                )
            }
        }
    }
}

struct RadarInsightCard: View {
    let insight: CivicRadarInsight

    var body: some View {
        CivicGlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 8) {
                    RectBadge(
                        text: insight.priority.label,
                        systemImage: insight.priority.systemImage,
                        tint: insight.priority.tint
                    )
                    Spacer()
                    Text(insight.issue.voteCountdownLabel)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.impactColor(for: insight.issue.urgencyTint))
                }

                Text(insight.issue.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(insight.reason)
                    .font(.system(size: 13))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(insight.priority.tint)
                    Text(insight.recommendedAction)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Spacer()
                }
            }
        }
    }
}

struct IssueWhyItMattersCard: View {
    let issue: CivicIssue
    let profile: UserProfile?
    let alreadySent: Bool

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "Why this matters", systemImage: "location.viewfinder")
                    Spacer()
                    RectBadge(
                        text: issue.recommendedAction(alreadySent: alreadySent),
                        systemImage: "arrow.right.circle.fill",
                        tint: CivicTheme.impactColor(for: issue.urgencyTint)
                    )
                }

                Text(issue.personalReason(for: profile))
                    .font(.system(size: 15, weight: .semibold))
                    .lineSpacing(3)
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(issue.timingSummary)
                    .font(.system(size: 13))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                let matchedFactors = profile?.factors.filter { !$0.topics.isDisjoint(with: issue.topics) } ?? []
                if !matchedFactors.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(matchedFactors).sorted(by: { $0.label < $1.label })) { factor in
                            RectBadge(text: factor.label, systemImage: factor.systemImage, tint: factor.tint)
                        }
                    }
                }
            }
        }
    }
}

struct CivicTrustCard: View {
    let issue: CivicIssue
    let onOpenSource: (URL) -> Void

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "Trust check", systemImage: "checkmark.shield.fill")
                    Spacer()
                    RectBadge(
                        text: "\(issue.trustScore)%",
                        systemImage: "gauge.medium",
                        tint: trustTint
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(issue.trustLabel)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Text("Backed by \(issue.sourceName). \(issue.sourceEvidenceText).")
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(CivicTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !issue.citations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(issue.citations.prefix(2)) { citation in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: "quote.opening")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(CivicTheme.green)
                                    .frame(width: 18, height: 18)
                                    .background(CivicTheme.green.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(citation.label)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(CivicTheme.ink)
                                    Text(citation.quote)
                                        .font(.system(size: 12))
                                        .lineLimit(2)
                                        .foregroundStyle(CivicTheme.mutedInk)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                }

                if let url = issue.sourceURLValue {
                    Button {
                        Haptics.selection()
                        onOpenSource(url)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "safari.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("Open source document")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(CivicTheme.cyan)
                        .padding(13)
                        .background(CivicTheme.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var trustTint: Color {
        if issue.trustScore >= 88 { return CivicTheme.green }
        if issue.trustScore >= 76 { return CivicTheme.cyan }
        return CivicTheme.amber
    }
}

private struct RadarMiniMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
    }
}
