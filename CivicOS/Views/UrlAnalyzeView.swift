import SwiftUI

/// "Paste any URL → Athen tells you what it is + what you can do."
/// Lives as a sheet you can open from the Assistant tab header.
/// Designed for the moment a user reads an article, hears a podcast,
/// or sees a tweet and thinks "what should I do about this?"
struct UrlAnalyzeView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var urlText: String = ""
    @State private var isAnalyzing: Bool = false
    @State private var result: CivicUrlAnalysis?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        intro
                        inputCard
                        if isAnalyzing { loadingCard }
                        if let err = errorMessage { errorBanner(err) }
                        if let result { resultCard(result) }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Read this for me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let pasted = UIPasteboard.general.string {
                            urlText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                            Haptics.selection()
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CivicTheme.violet)
                    }
                    .accessibilityLabel("Paste from clipboard")
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("READ THIS FOR ME", systemImage: "link.badge.plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.violet)
                .tracking(0.5)
            Text("Paste any article, tweet, or bill URL")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Athen reads the page, finds related items in your feed, and tells you what you could actually do today.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("https://…", text: $urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(size: 14, weight: .medium))
                .padding(12)
                .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(CivicTheme.hairline, lineWidth: 1))

            Button {
                Haptics.selection()
                Task { await analyze() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                    Text(isAnalyzing ? "Reading…" : "Analyze with Athen")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(canAnalyze ? CivicTheme.violet : CivicTheme.quietInk, in: RoundedRectangle(cornerRadius: 12))
                .opacity(canAnalyze ? 1 : 0.7)
            }
            .buttonStyle(.plain)
            .disabled(!canAnalyze)
        }
    }

    private var canAnalyze: Bool {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if isAnalyzing { return false }
        guard let url = URL(string: trimmed) else { return false }
        return url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https"
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(CivicTheme.violet)
            VStack(alignment: .leading, spacing: 2) {
                Text("Fetching the page…")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text("Reading + matching to your tracked items. Usually 5-15 sec.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CivicTheme.red)
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func resultCard(_ analysis: CivicUrlAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title = analysis.pageTitle, !title.isEmpty {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                    Text("WHAT THIS IS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(CivicTheme.violet)
                    Spacer()
                    AIDisclosureChip(surface: .brief, compact: true)
                }
                Text(analysis.summary)
                    .font(.system(size: 14, weight: .medium))
                    .lineSpacing(3)
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !analysis.relatedIssues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RELATED IN YOUR FEED")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(CivicTheme.cyan)
                    ForEach(analysis.relatedIssues) { item in
                        Button {
                            Haptics.selection()
                            if let id = UUID(uuidString: item.id),
                               store.issue(with: id) != nil {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    store.pendingDeepLinkIssueID = id
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(CivicTheme.cyan)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(CivicTheme.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(item.scope.uppercased())
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(CivicTheme.quietInk)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CivicTheme.quietInk)
                            }
                            .padding(12)
                            .background(CivicTheme.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(CivicTheme.cyan.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !analysis.suggestedActions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WHAT YOU COULD DO")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(CivicTheme.green)
                    ForEach(Array(analysis.suggestedActions.enumerated()), id: \.offset) { _, action in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(CivicTheme.green)
                            Text(action)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CivicTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private func analyze() async {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isAnalyzing = true
        errorMessage = nil
        result = nil
        defer { isAnalyzing = false }
        let outcome = await store.analyzeURL(trimmed)
        switch outcome {
        case .success(let analysis):
            result = analysis
        case .failure(let err):
            errorMessage = (err as? LocalizedError)?.errorDescription ?? err.localizedDescription
        }
    }
}
