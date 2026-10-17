import SwiftUI

/// Bill timeline — chronological events on one issue. Powered by
/// `/v1/issues/:id/timeline` which combines issue history with roll-call
/// votes from the VoteStore. Reporters use this to write "what happened
/// with HB1429" pieces; Hill staff use it to see where a bill is in the
/// pipeline at a glance.
struct BillTimelineCard: View {
    @Environment(CivicOSStore.self) private var store
    let issueId: String

    @State private var events: [CivicTimelineEvent] = []
    @State private var isLoading: Bool = false
    @State private var didLoad: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if isLoading && events.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().tint(CivicTheme.violet).scaleEffect(0.85)
                    Text("Building timeline…")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                }
            } else if events.isEmpty {
                Text("No timeline events on file for this bill yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(CivicTheme.quietInk)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                        eventRow(event, isLast: idx == events.count - 1)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.hairline, lineWidth: 1))
        .task(id: issueId) {
            if didLoad { return }
            didLoad = true
            isLoading = true
            events = await store.loadTimeline(issueId: issueId)
            isLoading = false
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "timeline.selection")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CivicTheme.violet)
            Text("BILL TIMELINE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(CivicTheme.violet)
            Spacer()
            if !events.isEmpty {
                Text("\(events.count) events")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
        }
    }

    private func eventRow(_ event: CivicTimelineEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(tint(for: event.kind))
                        .frame(width: 22, height: 22)
                    Image(systemName: icon(for: event.kind))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                if !isLast {
                    Rectangle()
                        .fill(CivicTheme.hairline)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 4)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Spacer()
                    Text(formattedDate(event.atISO))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.quietInk)
                }
                Text(event.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
    }

    private func icon(for kind: CivicTimelineEvent.Kind) -> String {
        switch kind {
        case .introduced: "doc.badge.plus"
        case .updated: "arrow.triangle.2.circlepath"
        case .voteScheduled: "calendar"
        case .votePassedDate: "calendar.badge.clock"
        case .rollCall: "hand.thumbsup.fill"
        }
    }

    private func tint(for kind: CivicTimelineEvent.Kind) -> Color {
        switch kind {
        case .introduced: CivicTheme.cyan
        case .updated: CivicTheme.amber
        case .voteScheduled: CivicTheme.violet
        case .votePassedDate: CivicTheme.quietInk
        case .rollCall: CivicTheme.green
        }
    }

    private func formattedDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso)
            ?? {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f.date(from: iso)
            }() else { return "" }
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        return df.string(from: date)
    }
}
