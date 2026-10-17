import SwiftUI

/// Compact banner that surfaces backend connectivity issues with a one-tap
/// fix. Drop into any screen's top edge — it auto-shows for `.offline` /
/// `.mockMode`, hides for `.online` / `.checking` / `.unknown`.
///
/// Tapping the CTA presents the same backend editor sheet the You tab uses,
/// so the user can correct the URL without leaving the current tab.
struct BackendOfflineBanner: View {
    @Environment(CivicOSStore.self) private var store
    @State private var showingEditor = false

    var body: some View {
        switch store.backendStatus {
        case .offline(let message, let baseURL):
            banner(
                tint: CivicTheme.red,
                icon: "exclamationmark.triangle.fill",
                title: "Backend offline",
                subtitle: "\(baseURL) — \(message)"
            )
        case .mockMode:
            banner(
                tint: CivicTheme.amber,
                icon: "bolt.slash.circle.fill",
                title: "Running on mock data",
                subtitle: "Connect a backend to unlock real AI briefs, audio, and filings."
            )
        case .online, .checking, .unknown:
            EmptyView()
        }
    }

    @ViewBuilder
    private func banner(tint: Color, icon: String, title: String, subtitle: String) -> some View {
        Button {
            Haptics.selection()
            showingEditor = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.18))
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text("Fix")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(tint, in: Capsule())
            }
            .padding(12)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingEditor) {
            BackendURLEditorSheet()
                .environment(store)
        }
    }
}
