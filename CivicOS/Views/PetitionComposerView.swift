import SwiftUI

/// Create a new petition. Two paths: attach to an existing civic issue
/// (auto-resolves target official + can seed body from the brief) or write
/// freeform (user provides title/ask/body). Form is intentionally compact.
struct PetitionComposerView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let prefilledIssueID: CivicIssue.ID?

    @State private var title: String = ""
    @State private var ask: String = ""
    @State private var petitionBody: String = ""
    @State private var signerDisplayName: String = ""
    @State private var threshold: String = "100"
    @State private var deadlineDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    @State private var attachedIssueID: CivicIssue.ID?
    @State private var showIssuePicker: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var inlineError: String?
    @State private var didSeedFromIssue: Bool = false

    init(prefilledIssueID: CivicIssue.ID? = nil) {
        self.prefilledIssueID = prefilledIssueID
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        intro
                        issuePickerRow
                        labeledField("PETITION TITLE", text: $title, placeholder: "Pass HB 1234 / Reject the rate hike / Hold a public hearing on…")
                        labeledField("THE ASK", text: $ask, placeholder: "Vote yes on HB 1234 by Friday.")
                        bodyField
                        thresholdField
                        deadlineField
                        labeledField("YOUR NAME (organizer)", text: $signerDisplayName, placeholder: "First Last")
                        if let inlineError {
                            Text(inlineError)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CivicTheme.red)
                                .padding(.top, 4)
                        }
                        createButton
                            .padding(.top, 8)
                        Color.clear.frame(height: 20)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Start a petition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
            .onAppear {
                if let prefilledIssueID, attachedIssueID == nil {
                    attachedIssueID = prefilledIssueID
                    seedFromIssueIfPossible()
                }
            }
            .sheet(isPresented: $showIssuePicker) {
                IssuePickerForPetitionSheet(selected: $attachedIssueID)
                    .environment(store)
            }
            .onChange(of: attachedIssueID) { _, _ in seedFromIssueIfPossible() }
        }
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("NEW PETITION", systemImage: "person.3.sequence.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.violet)
                .tracking(0.5)
            Text("Rally a collective demand")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Athen delivers your petition + every signer's name and ZIP straight to the official's inbox once the threshold or deadline hits.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var issuePickerRow: some View {
        Button {
            Haptics.selection()
            showIssuePicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
                    .frame(width: 36, height: 36)
                    .background(CivicTheme.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachedIssue == nil ? "Attach to an issue (optional)" : "Attached issue")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(CivicTheme.quietInk)
                    Text(attachedIssue?.title ?? "Tap to pick — auto-resolves the target official")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CivicTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var attachedIssue: CivicIssue? {
        guard let id = attachedIssueID else { return nil }
        return store.issue(with: id)
    }

    private var bodyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PETITION BODY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(CivicTheme.quietInk)
                Spacer()
                if didSeedFromIssue {
                    Text("Drafted from issue brief")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                }
            }
            TextEditor(text: $petitionBody)
                .scrollContentBackground(.hidden)
                .font(.system(size: 14))
                .frame(minHeight: 140)
                .padding(10)
                .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
        }
    }

    private var thresholdField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SIGNATURE THRESHOLD")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(CivicTheme.quietInk)
            HStack(spacing: 10) {
                TextField("100", text: $threshold)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
                    .keyboardType(.numberPad)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
                Text("signatures auto-deliver")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                Spacer(minLength: 0)
            }
        }
    }

    private var deadlineField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEADLINE")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(CivicTheme.quietInk)
            DatePicker("Deadline", selection: $deadlineDate, in: Date.now..., displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
        }
    }

    private var createButton: some View {
        Button {
            submit()
        } label: {
            HStack(spacing: 10) {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 14, weight: .bold))
                }
                Text(isSubmitting ? "Creating…" : "Publish petition")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(canSubmit ? CivicTheme.violet : CivicTheme.violet.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: CivicTheme.violet.opacity(0.30), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !ask.trimmingCharacters(in: .whitespaces).isEmpty
            && petitionBody.trimmingCharacters(in: .whitespaces).count >= 20
            && !signerDisplayName.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSubmitting
            && (attachedIssue != nil || !(store.profile?.zipCode.isEmpty ?? true))
    }

    // MARK: - Submit

    private func submit() {
        guard canSubmit else { return }
        Haptics.impact(.medium)
        isSubmitting = true
        inlineError = nil
        let formatter = ISO8601DateFormatter()
        let input = PetitionCreateInput(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            ask: ask.trimmingCharacters(in: .whitespacesAndNewlines),
            body: petitionBody.trimmingCharacters(in: .whitespacesAndNewlines),
            creatorDisplayName: signerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
            attachedIssueId: attachedIssueID?.uuidString,
            zip: store.profile?.zipCode,
            threshold: Int(threshold.trimmingCharacters(in: .whitespaces)),
            deadlineISO: formatter.string(from: deadlineDate),
            visibility: "public",
            targets: nil
        )
        Task {
            do {
                _ = try await store.createPetition(input)
                Haptics.success()
                dismiss()
            } catch {
                Haptics.error()
                inlineError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }

    // MARK: - Seeding

    private func seedFromIssueIfPossible() {
        guard let issue = attachedIssue else { return }
        // Only seed if the user hasn't typed yet.
        if title.isEmpty {
            title = "Take action on \(issue.title)"
        }
        if ask.isEmpty {
            ask = "Vote on \(issue.title) in a way that protects our community."
        }
        if petitionBody.isEmpty {
            // Pull the Claude brief if we have one; otherwise the issue summary.
            if let brief = store.brief(for: issue.id.uuidString) {
                petitionBody = "As constituents of \(issue.jurisdiction), we ask you to act on the following:\n\n\(brief.headline)\n\n\(brief.subhead)\n\n\(brief.lead)\n\nWe expect a substantive response indicating your position."
            } else {
                petitionBody = "As constituents of \(issue.jurisdiction), we ask you to act on \(issue.title).\n\n\(issue.summary)\n\nWe expect a substantive response indicating your position."
            }
            didSeedFromIssue = true
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(CivicTheme.quietInk)
            TextField(placeholder, text: text, axis: .vertical)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CivicTheme.ink)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
        }
    }
}

private struct IssuePickerForPetitionSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: CivicIssue.ID?

    var body: some View {
        NavigationStack {
            List(store.visibleIssues.sorted { $0.voteDate < $1.voteDate }) { issue in
                Button {
                    selected = issue.id
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(CivicTheme.ink)
                            .lineLimit(2)
                        Text(issue.jurisdiction)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CivicTheme.mutedInk)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Attach an issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
