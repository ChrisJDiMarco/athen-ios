import SwiftUI

/// Apple Guideline 1.2 requires user-generated content apps to provide a
/// reporting mechanism with a documented response time. This sheet captures
/// a categorized reason; the post is hidden from the reporter immediately
/// and POSTed to /v1/moderation/report on the backend, which persists it
/// to a human review queue with a 24-hour SLA.
struct ReportPostSheet: View {
    let post: SocialPost
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: ReportReason = .spam
    @State private var note: String = ""

    enum ReportReason: String, CaseIterable, Identifiable {
        case spam = "Spam or scam"
        case harassment = "Harassment or hate"
        case violence = "Threats or violence"
        case misinformation = "Election or civic misinformation"
        case selfHarm = "Self-harm"
        case impersonation = "Impersonating someone"
        case other = "Something else"

        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .spam: "envelope.badge.fill"
            case .harassment: "exclamationmark.bubble.fill"
            case .violence: "exclamationmark.triangle.fill"
            case .misinformation: "checkmark.shield.fill"
            case .selfHarm: "heart.fill"
            case .impersonation: "person.crop.circle.badge.questionmark.fill"
            case .other: "ellipsis.circle.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerBlock
                    reasonPicker
                    if selectedReason == .other {
                        noteField
                    }
                    policyBlock
                    submitButton
                    Color.clear.frame(height: 16)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            .background(CivicTheme.screenBackground.ignoresSafeArea())
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(CivicTheme.mutedInk)
                }
            }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Why are you reporting this post?")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Athen reviews every report within 24 hours. The post is hidden from your feed immediately.")
                .font(.system(size: 13))
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reasonPicker: some View {
        VStack(spacing: 8) {
            ForEach(ReportReason.allCases) { reason in
                Button {
                    Haptics.selection()
                    selectedReason = reason
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: reason.systemImage)
                            .frame(width: 22)
                            .foregroundStyle(selectedReason == reason ? CivicTheme.red : CivicTheme.cyan)
                        Text(reason.rawValue)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CivicTheme.ink)
                        Spacer()
                        if selectedReason == reason {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(CivicTheme.red)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        selectedReason == reason ? CivicTheme.red.opacity(0.08) : CivicTheme.panel,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selectedReason == reason ? CivicTheme.red.opacity(0.4) : CivicTheme.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tell us more (optional)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
            TextEditor(text: $note)
                .font(.system(size: 14))
                .frame(minHeight: 88)
                .padding(8)
                .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(CivicTheme.hairline, lineWidth: 1))
        }
    }

    private var policyBlock: some View {
        Text("Athen has zero tolerance for objectionable content or abusive users. Reports are reviewed by humans within 24 hours and can result in content removal or account blocks. See our content policy in Settings → Legal.")
            .font(.system(size: 11))
            .foregroundStyle(CivicTheme.quietInk)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var submitButton: some View {
        Button {
            let payload: String = selectedReason == .other && !note.isEmpty
                ? "\(selectedReason.rawValue): \(note)"
                : selectedReason.rawValue
            onSubmit(payload)
        } label: {
            Text("Submit report")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(CivicTheme.red, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
