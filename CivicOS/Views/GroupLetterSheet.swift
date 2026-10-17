import SwiftUI

/// Foundation flow for a co-signed group letter: pick an issue, edit a
/// shared subject + body, gather co-signs from group members, mark sent.
/// All local for now — no network filing yet. The "Send" button writes a
/// sent timestamp so the letter shows up in history.
struct GroupLetterSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let group: OutreachGroup
    @State private var existingLetterID: GroupLetter.ID?
    @State private var pickedIssueID: CivicIssue.ID?
    @State private var subjectDraft: String = ""
    @State private var bodyDraft: String = ""
    @State private var didMarkSent: Bool = false
    @State private var showIssuePicker: Bool = false

    init(group: OutreachGroup, existing: GroupLetter? = nil) {
        self.group = group
        self._existingLetterID = State(initialValue: existing?.id)
        self._pickedIssueID = State(initialValue: existing?.issueID)
        self._subjectDraft = State(initialValue: existing?.subject ?? "")
        self._bodyDraft = State(initialValue: existing?.body ?? "")
        self._didMarkSent = State(initialValue: existing?.isSent ?? false)
    }

    private var letter: GroupLetter? {
        guard let existingLetterID else { return nil }
        return store.groupLetters.first { $0.id == existingLetterID }
    }

    private var pickedIssue: CivicIssue? {
        guard let pickedIssueID else { return nil }
        return store.issue(with: pickedIssueID)
    }

    private var unsignedMembers: [GroupMember] {
        let signedMemberIDs = Set((letter?.signers ?? []).compactMap { $0.memberID })
        return group.members.filter { !signedMemberIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        intro
                        issuePickerRow
                        if pickedIssue != nil {
                            subjectField
                            bodyField
                            startOrUpdateRow
                            if let letter {
                                signersSection(letter)
                                if !didMarkSent {
                                    markSentButton(letter)
                                } else {
                                    sentBadge(letter)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(existingLetterID == nil ? "Group letter" : "Edit letter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
            }
            .sheet(isPresented: $showIssuePicker) {
                IssuePickerSheet(selected: $pickedIssueID)
                    .environment(store)
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("GROUP LETTER", systemImage: "person.2.crop.square.stack.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.violet)
                .tracking(0.5)
            Text("One letter, many signers")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Draft a shared message, gather co-signs from your crew, then mark it sent. Filing as a group hits harder than five separate emails.")
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
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
                    .frame(width: 40, height: 40)
                    .background(CivicTheme.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(pickedIssue == nil ? "Pick an issue" : "Issue")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(CivicTheme.quietInk)
                    Text(pickedIssue?.title ?? "Tap to choose")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CivicTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var subjectField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SUBJECT")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(CivicTheme.quietInk)
            TextField("e.g. Crew of \(group.members.count + 1) urges yes on…", text: $subjectDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(12)
                .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
        }
    }

    private var bodyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MESSAGE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(CivicTheme.quietInk)
            TextEditor(text: $bodyDraft)
                .scrollContentBackground(.hidden)
                .font(.system(size: 14))
                .frame(minHeight: 180)
                .padding(8)
                .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
        }
    }

    private var startOrUpdateRow: some View {
        Button {
            Haptics.selection()
            commitDraft()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: existingLetterID == nil ? "square.and.pencil" : "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                Text(existingLetterID == nil ? "Start co-signing" : "Save changes")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(CivicTheme.violet, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(pickedIssue == nil || subjectDraft.trimmingCharacters(in: .whitespaces).isEmpty || bodyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func signersSection(_ letter: GroupLetter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CO-SIGNERS · \(letter.signers.count)")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(CivicTheme.violet)
                Spacer()
            }
            FlowLayout(spacing: 6) {
                ForEach(letter.signers) { signer in
                    HStack(spacing: 6) {
                        Text(signer.initials)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(CivicTheme.violet, in: Circle())
                        Text(signer.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CivicTheme.ink)
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, 10)
                    .padding(.vertical, 4)
                    .background(CivicTheme.violet.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(CivicTheme.violet.opacity(0.20), lineWidth: 1))
                }
            }
            if !unsignedMembers.isEmpty && !didMarkSent {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ADD A CO-SIGN")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(CivicTheme.quietInk)
                    VStack(spacing: 8) {
                        ForEach(unsignedMembers) { member in
                            Button {
                                Haptics.selection()
                                store.signGroupLetter(letter.id, member: member)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(member.initials)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(CivicTheme.cyan, in: Circle())
                                    Text(member.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(CivicTheme.ink)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(CivicTheme.cyan)
                                }
                                .padding(10)
                                .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(CivicTheme.hairline, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func markSentButton(_ letter: GroupLetter) -> some View {
        Button {
            Haptics.selection()
            store.markGroupLetterSent(letter.id)
            didMarkSent = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                Text("Mark as sent")
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(CivicTheme.green, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func sentBadge(_ letter: GroupLetter) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(CivicTheme.green)
            Text("Sent with \(letter.signerCount) co-sign\(letter.signerCount == 1 ? "" : "s")")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CivicTheme.green)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(CivicTheme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func commitDraft() {
        guard let pickedIssue else { return }
        let subject = subjectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = bodyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = letter {
            store.updateGroupLetter(existing.id, subject: subject, body: body)
        } else {
            let new = store.startGroupLetter(
                group: group,
                issue: pickedIssue,
                subject: subject,
                body: body
            )
            existingLetterID = new.id
        }
    }
}

private struct IssuePickerSheet: View {
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
            .navigationTitle("Pick an issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
