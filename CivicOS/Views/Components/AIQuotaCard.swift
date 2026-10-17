import SwiftUI

/// Renders the install's per-day AI-quota state in the You tab so users
/// know up front how much Claude / ElevenLabs capacity they have left.
///
/// Loads lazily on appear. If the backend isn't reachable the card just
/// stays silent (no scary error states for a non-essential view).
struct AIQuotaCard: View {
    @Environment(CivicOSStore.self) private var store
    @State private var usage: [AthenQuotaUsage] = []
    @State private var isLoading: Bool = false
    @State private var hasLoaded: Bool = false

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                if isLoading && usage.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Checking your daily allowance…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                    }
                } else if usage.isEmpty {
                    Text("You haven't tapped any AI features yet today. Each category resets at midnight UTC.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(usage) { row in
                            quotaRow(row)
                        }
                    }
                    Text("Each category resets at midnight UTC.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CivicTheme.quietInk)
                }
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await load()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CivicTheme.cyan)
            Text("Today's AI allowance")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh quota")
        }
    }

    private func quotaRow(_ row: AthenQuotaUsage) -> some View {
        let percent = row.max > 0 ? Double(row.used) / Double(row.max) : 0
        let warn = percent >= 0.8
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.displayLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
                Spacer()
                Text(detailText(for: row))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(warn ? CivicTheme.red : CivicTheme.mutedInk)
                    .monospacedDigit()
            }
            ProgressView(value: min(1.0, percent))
                .progressViewStyle(.linear)
                .tint(warn ? CivicTheme.red : CivicTheme.cyan)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.displayLabel): \(row.remaining) of \(row.max) remaining today")
    }

    private func detailText(for row: AthenQuotaUsage) -> String {
        if row.name == "elevenlabs:tts" {
            return "\(formatChars(row.remaining)) left"
        }
        return "\(row.remaining) of \(row.max) left"
    }

    private func formatChars(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk chars", Double(count) / 1000.0)
        }
        return "\(count) chars"
    }

    private func load() async {
        guard let url = store.effectiveBackendURL else { return }
        isLoading = true
        defer { isLoading = false }
        let service = HTTPQuotaService(baseURL: url)
        do {
            let fetched = try await service.fetchUsage()
            usage = fetched
        } catch {
            // Silent — non-essential card.
        }
    }
}
