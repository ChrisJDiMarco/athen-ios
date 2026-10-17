import SwiftUI

/// Live slide-up drawer that ticks each source off as the SSE stream from
/// `/v1/refresh/stream` reports back. Used by Home's refresh button to
/// replace the "blind spinner" with real per-connector progress.
struct RefreshProgressDrawer: View {
    let startedAt: Date?
    let rows: [Row]
    let summary: Summary?
    let errorMessage: String?
    let onDismiss: () -> Void

    struct Row: Identifiable, Equatable {
        let id: String
        let name: String
        var status: Status
        var inspected: Int?
        var inserted: Int?
        var updated: Int?
        var errorMessage: String?

        enum Status: Equatable {
            case running
            case ok
            case skipped(String?)
            case failed
        }
    }

    struct Summary: Equatable {
        let totalInserted: Int
        let totalUpdated: Int
        let totalIssues: Int
        let durationMs: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(spacing: 8) {
                ForEach(rows) { row in
                    rowView(row)
                }
                if rows.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Reaching the sources…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                        Spacer()
                    }
                }
            }

            if let summary {
                summaryBar(summary)
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.red)
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(CivicTheme.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            if summary != nil || errorMessage != nil {
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(CivicTheme.cyan, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CivicTheme.hairline, lineWidth: 1),
        )
        .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 12)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(CivicTheme.cyan.opacity(0.16))
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Refreshing your sources")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                if let startedAt {
                    Text(elapsedLabel(startedAt))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.quietInk)
                        .monospacedDigit()
                }
            }
            Spacer()
            if summary != nil || errorMessage != nil {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .frame(width: 30, height: 30)
                        .background(CivicTheme.panelElevated, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 12) {
            statusGlyph(for: row.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
                    .lineLimit(1)
                Text(detail(for: row))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineLimit(2)
            }
            Spacer()
            if let inserted = row.inserted, inserted > 0 {
                Text("+\(inserted)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.green)
                    .monospacedDigit()
            } else if let updated = row.updated, updated > 0 {
                Text("·\(updated)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(CivicTheme.panelElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func statusGlyph(for status: Row.Status) -> some View {
        switch status {
        case .running:
            ProgressView().controlSize(.mini).tint(CivicTheme.cyan)
                .frame(width: 18, height: 18)
        case .ok:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CivicTheme.green)
        case .skipped:
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CivicTheme.red)
        }
    }

    private func detail(for row: Row) -> String {
        switch row.status {
        case .running:
            return "Reaching out…"
        case .ok:
            let inspected = row.inspected ?? 0
            let inserted = row.inserted ?? 0
            let updated = row.updated ?? 0
            if inserted == 0 && updated == 0 { return "Inspected \(inspected) — nothing new" }
            return "Inspected \(inspected) · \(inserted) new · \(updated) updated"
        case .skipped(let reason):
            return reason ?? "Skipped"
        case .failed:
            return row.errorMessage ?? "Couldn't reach this source"
        }
    }

    private func summaryBar(_ summary: Summary) -> some View {
        HStack(spacing: 14) {
            label("New", value: "\(summary.totalInserted)", tint: CivicTheme.green)
            label("Updated", value: "\(summary.totalUpdated)", tint: CivicTheme.cyan)
            label("Total", value: "\(summary.totalIssues)", tint: CivicTheme.violet)
            Spacer()
            Text("\(Double(summary.durationMs) / 1000.0, specifier: "%.1f")s")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CivicTheme.quietInk)
                .monospacedDigit()
        }
    }

    private func label(_ title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .textCase(.uppercase)
                .tracking(0.4)
        }
    }

    private func elapsedLabel(_ start: Date) -> String {
        let secs = Date.now.timeIntervalSince(start)
        return String(format: "Started %0.1fs ago", secs)
    }
}
