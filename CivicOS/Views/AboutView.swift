import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var presentedDoc: AboutDoc?

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        heroCard
                        infoSection
                        legalSection
                        footerNote
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Haptics.selection()
                        dismiss()
                    }
                    .foregroundStyle(CivicTheme.cyan)
                }
            }
            .sheet(item: $presentedDoc) { doc in
                switch doc {
                case .privacy:
                    LegalDocumentView(document: .privacy)
                case .terms:
                    LegalDocumentView(document: .terms)
                case .contact:
                    AboutDocSheet(doc: .contact)
                }
            }
        }
    }

    private var heroCard: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CivicTheme.cyan.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(CivicTheme.cyan)
                }
                Text(AppBrand.name)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text("A Local Impact Translator and Auto-Filer. We turn dense civic packets into a button you can tap.")
                    .font(.system(size: 14))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Version \(version)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CivicTheme.quietInk)
            }
        }
    }

    private var infoSection: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 0) {
                row("Made with",
                    value: "SwiftUI, Anthropic Claude, Census Geocoder, Open States, Firecrawl",
                    isFirst: true)
                divider
                row("Open data",
                    value: "@unitedstates/congress-legislators for the U.S. Congress directory.")
                divider
                row("Filings",
                    value: "v1 records every filing locally with a confirmation code. Direct delivery to officials' offices ships in a later release. Connect Gmail to send from your own inbox today.")
            }
        }
    }

    private var legalSection: some View {
        CivicGlassCard {
            VStack(spacing: 0) {
                rowLink("Privacy policy", icon: "lock.shield.fill", isFirst: true) {
                    presentedDoc = .privacy
                }
                divider
                rowLink("Terms of use", icon: "doc.text.fill") {
                    presentedDoc = .terms
                }
                divider
                rowLink("Contact", icon: "envelope.fill") {
                    presentedDoc = .contact
                }
            }
        }
    }

    private var footerNote: some View {
        Text("\(AppBrand.name) is not affiliated with any government body. Briefs and filings are AI-generated and presented for your review.")
            .font(.system(size: 12))
            .foregroundStyle(CivicTheme.quietInk)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.top, 6)
    }

    private var divider: some View {
        Rectangle().fill(CivicTheme.hairline).frame(height: 1)
    }

    private func row(_ label: String, value: String, isFirst: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, isFirst ? 0 : 12)
        .padding(.top, isFirst ? 0 : 0)
    }

    private func rowLink(_ label: String, icon: String, isFirst: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CivicTheme.cyan)
                    .frame(width: 22)
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            .padding(.vertical, isFirst ? 0 : 14)
            .padding(.top, isFirst ? 0 : 0)
        }
        .buttonStyle(.plain)
    }
}

enum AboutDoc: Identifiable {
    case privacy, terms, contact
    var id: String { String(describing: self) }
}

private struct AboutDocSheet: View {
    @Environment(\.dismiss) private var dismiss
    let doc: AboutDoc

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        Text(docText)
                            .font(.system(size: 14))
                            .lineSpacing(5)
                            .foregroundStyle(CivicTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
        }
    }

    private var title: String {
        switch doc {
        case .privacy: "Privacy"
        case .terms: "Terms"
        case .contact: "Contact"
        }
    }

    private var docText: String {
        // Only `.contact` is actually rendered here — `.privacy` and `.terms`
        // are routed to LegalDocumentView in the parent. The cases are
        // kept for type completeness but never produce output for those paths.
        switch doc {
        case .privacy, .terms:
            return ""
        case .contact:
            return """
            We're building \(AppBrand.name) in public.

            For anything — bug reports, feature requests, factual corrections, or just to say hi:
            chris@logicoutloud.com

            We aim to respond within 48 hours.

            If you've found an inaccuracy on a bill, an official's contact details, or a missed deadline, please include the source URL so we can verify and fix at the data layer.
            """
        }
    }
}

#Preview {
    AboutView()
}
