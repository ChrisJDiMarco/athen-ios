import SwiftUI

/// Renders a bundled markdown document (Privacy or Terms) inside the app
/// so App Store reviewers — and curious users — never have to leave Athen
/// to read what we collect or what they're agreeing to.
struct LegalDocumentView: View {
    enum Document {
        case privacy
        case terms

        var resourceName: String {
            switch self {
            case .privacy: "Privacy"
            case .terms: "Terms"
            }
        }

        var screenTitle: String {
            switch self {
            case .privacy: "Privacy Policy"
            case .terms: "Terms of Service"
            }
        }
    }

    let document: Document
    @Environment(\.dismiss) private var dismiss
    @State private var rendered: AttributedString = AttributedString("")
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let loadError {
                            errorState(loadError)
                        } else {
                            Text(rendered)
                                .font(.system(size: 15))
                                .lineSpacing(4)
                                .foregroundStyle(CivicTheme.ink)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle(document.screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .task { load() }
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(CivicTheme.amber)
            Text("Could not load this document")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() {
        guard
            let url = Bundle.main.url(forResource: document.resourceName, withExtension: "md"),
            let raw = try? String(contentsOf: url, encoding: .utf8)
        else {
            loadError = "Bundled file \(document.resourceName).md not found in app resources."
            return
        }
        do {
            // SwiftUI's AttributedString markdown parser handles headings,
            // bold, italic, lists, links — the same flavor as the .md files.
            let options = AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
            rendered = try AttributedString(markdown: raw, options: options)
        } catch {
            // Fallback to plain text if markdown parsing fails.
            rendered = AttributedString(raw)
        }
    }
}

#Preview {
    LegalDocumentView(document: .privacy)
}
