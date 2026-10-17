import SwiftUI

/// Reusable chip that surfaces "this content is AI-generated" — required by
/// Apple's evolving AI disclosure expectations and just generally good
/// practice for any user-facing AI content.
///
/// Tap it to read a one-paragraph explainer in a popover.
struct AIDisclosureChip: View {
    enum Surface: String {
        case brief = "AI BRIEF"
        case plan = "AI PLAN"
        case draft = "AI DRAFT"
        case audio = "AI AUDIO"
        case translation = "AI TRANSLATION"
    }

    let surface: Surface
    var compact: Bool = false

    @State private var showExplainer = false

    var body: some View {
        Button {
            Haptics.selection()
            showExplainer.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: compact ? 9 : 10, weight: .bold))
                Text(surface.rawValue)
                    .font(.system(size: compact ? 9 : 10, weight: .bold))
                    .tracking(0.5)
                Image(systemName: "info.circle")
                    .font(.system(size: compact ? 8 : 9, weight: .semibold))
            }
            .foregroundStyle(CivicTheme.violet)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 3 : 4)
            .background(CivicTheme.violet.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(surface.rawValue) — AI-generated content. Tap to learn more.")
        .popover(isPresented: $showExplainer) {
            explainer
                .presentationCompactAdaptation(.popover)
        }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(CivicTheme.violet)
                Text(headline)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
            }
            Text(bodyText)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("Athen always cites the official source. If something looks off, tap through to read the original — and let us know.")
                .font(.system(size: 12))
                .foregroundStyle(CivicTheme.quietInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: 320)
    }

    private var headline: String {
        switch surface {
        case .brief: "AI-written brief"
        case .plan: "AI-generated plan"
        case .draft: "AI-drafted letter"
        case .audio: "AI-voiced briefing"
        case .translation: "AI translation"
        }
    }

    private var bodyText: String {
        switch surface {
        case .brief:
            return "Athen reads the bill text and writes this plain-English explainer with Anthropic Claude. AI can summarize but can also make mistakes — verify the source before quoting."
        case .plan:
            return "Athen sends your situation (no personally identifying details beyond ZIP) to Claude to map you to relevant programs and steps. The plan is a starting point, not legal advice."
        case .draft:
            return "Claude drafts this letter using the bill's facts and your stance. You review every word before anything is filed or sent."
        case .audio:
            return "Claude writes the script using cached bill briefs; ElevenLabs voices it. No personal data is sent to ElevenLabs — only the script."
        case .translation:
            return "Claude translates the brief in real time. Best-effort — verify with a native speaker for high-stakes use."
        }
    }
}
