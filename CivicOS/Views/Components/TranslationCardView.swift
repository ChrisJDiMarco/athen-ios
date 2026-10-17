import SwiftUI

struct TranslationCardView: View {
    let issue: CivicIssue

    var body: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionHeader(title: "Translation", systemImage: "text.magnifyingglass")
                    Spacer()
                    Text(issue.zipCode)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.quietInk)
                }

                VStack(spacing: 0) {
                    ForEach(Array(issue.facts.enumerated()), id: \.element.id) { index, fact in
                        TranslationFactRow(fact: fact)

                        if index < issue.facts.count - 1 {
                            Divider()
                                .overlay(CivicTheme.hairline)
                                .padding(.leading, 38)
                        }
                    }
                }
                .background(CivicTheme.panelElevated)
                .clipShape(RoundedRectangle(cornerRadius: CivicTheme.mediumRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CivicTheme.mediumRadius, style: .continuous)
                        .stroke(CivicTheme.hairline, lineWidth: 1)
                )
            }
        }
    }
}

private struct TranslationFactRow: View {
    let fact: TranslationFact

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: fact.systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CivicTheme.cyan)
                .frame(width: 26)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(fact.label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)

                Text(fact.value)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(CivicTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
    }
}
