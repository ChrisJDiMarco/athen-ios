import SwiftUI

struct CivicGlassCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CivicTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: CivicTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CivicTheme.cornerRadius, style: .continuous)
                    .stroke(CivicTheme.hairline, lineWidth: 1)
            }
            .shadow(color: CivicTheme.cardShadow, radius: 18, x: 0, y: 8)
    }
}

struct RectBadge: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))

            Text(text)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(tint.opacity(0.20), lineWidth: 1)
        }
    }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CivicTheme.cyan)

            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CivicTheme.mutedInk)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }
}
