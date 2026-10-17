import SwiftUI

struct GroupDetailView: View {
    @Environment(CivicOSStore.self) private var store
    let group: OutreachGroup
    @State private var showingAddMember = false
    @State private var showingNewLetter = false
    @State private var editingLetter: GroupLetter?

    private var liveGroup: OutreachGroup {
        store.group(with: group.id) ?? group
    }

    private var letters: [GroupLetter] {
        store.letters(for: group.id)
    }

    var body: some View {
        ZStack {
            CivicTheme.screenBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    statsRow
                    if BetaFeatures.groupLetters {
                        groupLettersSection
                    }
                    membersSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddMember) {
            AddMemberSheet(groupID: group.id)
        }
        .sheet(isPresented: $showingNewLetter) {
            GroupLetterSheet(group: liveGroup)
                .environment(store)
        }
        .sheet(item: $editingLetter) { letter in
            GroupLetterSheet(group: liveGroup, existing: letter)
                .environment(store)
        }
    }

    @ViewBuilder
    private var groupLettersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Group letters")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Button {
                    Haptics.selection()
                    showingNewLetter = true
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CivicTheme.violet)
                }
                .buttonStyle(.plain)
            }
            if letters.isEmpty {
                Text("One co-signed letter often hits harder than five individual emails. Draft one together.")
                    .font(.system(size: 13))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(2)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CivicTheme.violet.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.violet.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            } else {
                ForEach(letters) { letter in
                    Button {
                        Haptics.selection()
                        editingLetter = letter
                    } label: {
                        groupLetterRow(letter)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }

    private func groupLetterRow(_ letter: GroupLetter) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill((letter.isSent ? CivicTheme.green : CivicTheme.violet).opacity(0.15))
                Image(systemName: letter.isSent ? "checkmark.seal.fill" : "doc.text.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(letter.isSent ? CivicTheme.green : CivicTheme.violet)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(letter.subject.isEmpty ? "Untitled letter" : letter.subject)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                    .lineLimit(1)
                Text("\(letter.signerCount) signer\(letter.signerCount == 1 ? "" : "s") · \(letter.issueTitle)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.quietInk)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: CivicTheme.cornerRadius)
                    .fill(CivicTheme.violet.opacity(0.15))
                Text(liveGroup.emoji)
                    .font(.system(size: 36))
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(liveGroup.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text("Created \(relativeDate(liveGroup.createdAt))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
            }
            Spacer()
        }
    }

    private var statsRow: some View {
        CivicGlassCard {
            HStack(spacing: 12) {
                stat(value: "\(liveGroup.members.count)", label: "Members", tint: CivicTheme.cyan)
                Divider().overlay(CivicTheme.hairline)
                stat(value: "\(liveGroup.totalRallies)", label: "Rallies sent", tint: CivicTheme.violet)
                Divider().overlay(CivicTheme.hairline)
                stat(value: "\(liveGroup.activeMemberCount)", label: "Active", tint: CivicTheme.green)
            }
        }
    }

    private func stat(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CivicTheme.quietInk)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var membersSection: some View {
        HStack {
            Text("Members")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CivicTheme.mutedInk)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            Button {
                showingAddMember = true
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.cyan)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)

        if liveGroup.members.isEmpty {
            emptyMembersState
        } else {
            VStack(spacing: 8) {
                ForEach(liveGroup.members) { member in
                    MemberRow(member: member, groupID: liveGroup.id)
                }
            }
        }
    }

    private var emptyMembersState: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("No one in this crew yet", systemImage: "person.crop.circle.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.amber)
                Text("Add the people you'd actually text about a city council vote — neighbors, parents from school, the group chat that cares.")
                    .font(.system(size: 14))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
                Button {
                    showingAddMember = true
                } label: {
                    HStack {
                        Text("Add first member")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(CivicTheme.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                    .foregroundStyle(CivicTheme.cyan)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

private struct MemberRow: View {
    @Environment(CivicOSStore.self) private var store
    let member: GroupMember
    let groupID: OutreachGroup.ID
    @State private var showShareSheet = false

    private var outreachText: String {
        let lastRally = member.rallyEvents.last
        if let event = lastRally {
            return "Hey \(member.name) — there's a vote on \(event.issueTitle). \(AppBrand.name) makes it 30 seconds. Want me to send you the link?"
        }
        return "Hey \(member.name) — I've been using \(AppBrand.name) to file with my reps on local votes. Takes 30 seconds. Want me to send you the link?"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(CivicTheme.cyan.opacity(0.15))
                Text(member.emoji)
                    .font(.system(size: 20))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(member.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CivicTheme.ink)
                Text(member.rallyEvents.isEmpty
                    ? "Never rallied"
                    : "\(member.rallyEvents.count) rall\(member.rallyEvents.count == 1 ? "y" : "ies") sent")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
            }

            Spacer()

            ShareLink(item: outreachText) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
                    .frame(width: 38, height: 38)
                    .background(CivicTheme.cyan.opacity(0.12), in: Circle())
            }
        }
        .padding(12)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                .stroke(CivicTheme.hairline, lineWidth: 1)
        )
        .shadow(color: CivicTheme.cardShadow, radius: 6, x: 0, y: 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.removeMember(member.id, from: groupID)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

private struct AddMemberSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let groupID: OutreachGroup.ID

    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var emoji: String = "🙂"
    @FocusState private var nameFocused: Bool

    private let emojiOptions = ["🙂", "😎", "🤓", "🦊", "🐝", "🦉", "🌿", "🐢", "👵", "🧑‍🎓"]

    var body: some View {
        ZStack {
            CivicTheme.screenBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("Add member")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .textCase(.uppercase)
                    TextField("Friend's name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CivicTheme.ink)
                        .focused($nameFocused)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                                .stroke(CivicTheme.hairline, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Phone or @handle (optional)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .textCase(.uppercase)
                    TextField("+1 555-…  or @handle", text: $phone)
                        .textFieldStyle(.plain)
                        .keyboardType(.phonePad)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(CivicTheme.ink)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                                .stroke(CivicTheme.hairline, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Emoji")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .textCase(.uppercase)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(emojiOptions, id: \.self) { e in
                            Button {
                                emoji = e
                            } label: {
                                Text(e)
                                    .font(.system(size: 22))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(emoji == e ? CivicTheme.cyan.opacity(0.18) : CivicTheme.panel, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                                            .stroke(emoji == e ? CivicTheme.cyan : CivicTheme.hairline, lineWidth: emoji == e ? 1.5 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let phoneTrimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.addMember(
                        GroupMember(name: trimmed, emoji: emoji, phoneOrHandle: phoneTrimmed.isEmpty ? nil : phoneTrimmed),
                        to: groupID
                    )
                    dismiss()
                } label: {
                    HStack {
                        Text("Add to crew")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 18)
                    .background(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? CivicTheme.quietInk : CivicTheme.cyan, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                    .shadow(color: CivicTheme.cyan.opacity(0.25), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
        .presentationDetents([.large])
        .onAppear { nameFocused = true }
    }
}
