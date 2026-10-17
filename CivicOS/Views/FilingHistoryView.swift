import SwiftUI

struct FilingHistoryView: View {
    @Environment(CivicOSStore.self) private var store

    var body: some View {
        ZStack {
            CivicTheme.screenBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if store.filingHistory.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.filingHistory) { entry in
                            NavigationLink(value: entry.issue.id) {
                                FilingHistoryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: CivicIssue.ID.self) { id in
            if let issue = store.issue(with: id) {
                IssueDetailView(issue: issue)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("History")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("\(store.filingHistory.count) filing\(store.filingHistory.count == 1 ? "" : "s") recorded. Every entry keeps a confirmation code and the exact message you reviewed.")
                .font(.system(size: 14))
                .foregroundStyle(CivicTheme.mutedInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Nothing filed yet", systemImage: "tray")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.amber)
                Text("When you endorse or oppose an item, it shows up here with the confirmation code and the full message. Direct delivery to officials is rolling out in a later release.")
                    .font(.system(size: 14))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
            }
        }
    }
}

private struct FilingHistoryRow: View {
    let entry: CivicOSStore.FilingHistoryEntry

    private var tint: Color {
        entry.receipt.action == .endorse ? CivicTheme.green : CivicTheme.red
    }

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(entry.receipt.action.rawValue.uppercased(), systemImage: entry.receipt.action.systemImage)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                        .tracking(0.5)
                    Spacer()
                    Text(entry.receipt.sentAt, style: .relative)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CivicTheme.quietInk)
                }

                Text(entry.issue.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.cyan)
                    Text(entry.receipt.officialName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(entry.receipt.confirmationCode)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(tint.opacity(0.12), in: Capsule())

                    if entry.receipt.channel == .recordedLocal {
                        Label("Recorded", systemImage: "tray.full.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CivicTheme.cyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(CivicTheme.cyan.opacity(0.12), in: Capsule())
                    } else if entry.receipt.queued {
                        Label("Queued", systemImage: "tray.and.arrow.up.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CivicTheme.amber)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(CivicTheme.amber.opacity(0.12), in: Capsule())
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CivicTheme.quietInk)
                }
            }
        }
    }
}
