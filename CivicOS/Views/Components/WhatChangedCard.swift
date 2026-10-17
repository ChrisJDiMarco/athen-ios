import SwiftUI

/// Compact "what changed since you last visited" card on Home. Aggregates
/// recent CivicDiffEvents on bookmarked items plus a count of any other
/// fresh activity. Tap a row to drill into the affected issue. Long-press
/// or the X button on the header dismisses all events at once.
struct WhatChangedCard: View {
    @Environment(CivicOSStore.self) private var store
    let onOpenIssue: (CivicIssue.ID) -> Void

    private var visibleEvents: [CivicDiffEvent] {
        // Show only events newer than the previous-launch timestamp so old
        // changes don't pile up forever.
        let cutoff = store.previousLastOpenedAt ?? .distantPast
        let recent = store.diffEvents.filter { $0.detectedAt >= cutoff }
        // Always cap at 5 for the home card; full list lives in You/History.
        return Array(recent.prefix(5))
    }

    private var newPostsSinceVisit: Int {
        let cutoff = store.previousLastOpenedAt ?? .distantPast
        return store.socialPosts.filter { $0.createdAt >= cutoff && store.isMyPost($0) == false }.count
    }

    private var hasContent: Bool {
        !visibleEvents.isEmpty || newPostsSinceVisit > 0
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                    Text("SINCE YOU LAST VISITED")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(CivicTheme.violet)
                    Spacer(minLength: 4)
                    Button {
                        Haptics.selection()
                        store.clearAllDiffs()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CivicTheme.quietInk)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss changes")
                }

                if visibleEvents.isEmpty == false {
                    VStack(spacing: 8) {
                        ForEach(visibleEvents) { event in
                            Button {
                                Haptics.selection()
                                onOpenIssue(event.issueID)
                                store.acknowledgeDiff(event.id)
                            } label: {
                                eventRow(event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if newPostsSinceVisit > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CivicTheme.cyan)
                            .frame(width: 22, height: 22)
                            .background(CivicTheme.cyan.opacity(0.14), in: Circle())
                        Text("\(newPostsSinceVisit) new post\(newPostsSinceVisit == 1 ? "" : "s") on Square")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CivicTheme.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CivicTheme.violet.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.violet.opacity(0.20), lineWidth: 1))
        }
    }

    private func eventRow(_ event: CivicDiffEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.kind.systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(event.kind.tint)
                .frame(width: 26, height: 26)
                .background(event.kind.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(event.kind.label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(event.kind.tint)
                Text(event.issueTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let plain = event.plainEnglish, !plain.isEmpty {
                    Text(plain)
                        .font(.system(size: 11))
                        .lineSpacing(2)
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
        }
        .padding(10)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CivicTheme.hairline, lineWidth: 1))
    }
}
