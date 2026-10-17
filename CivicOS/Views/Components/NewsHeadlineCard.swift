import SwiftUI

/// Single news headline row used by Home → News mode. Tap opens the source
/// article in Safari (Google News redirect resolves to the publisher).
struct NewsHeadlineCard: View {
    let headline: NewsHeadline
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            Haptics.selection()
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    sourceBadge
                    Spacer()
                    if let date = headline.publishedAt {
                        Text(date, style: .relative)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CivicTheme.quietInk)
                            .monospacedDigit()
                    }
                }
                Text(headline.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                if let snippet = headline.snippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 4) {
                    Text("Open article")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CivicTheme.cyan)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(headline.title), \(headline.source)")
    }

    private var sourceBadge: some View {
        HStack(spacing: 5) {
            Circle().fill(CivicTheme.cyan).frame(width: 5, height: 5)
            Text(headline.source.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(CivicTheme.mutedInk)
        }
    }
}

/// Soft pulsing animation for "live" status dots.
struct PulsingDot: ViewModifier {
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    scale = 1.35
                }
            }
    }
}
