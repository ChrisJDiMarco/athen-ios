import SwiftUI

struct GroupsListView: View {
    @Environment(CivicOSStore.self) private var store
    @State private var showingNewGroup = false

    var body: some View {
        ZStack {
            CivicTheme.screenBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if store.groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.groups) { group in
                            NavigationLink(value: group.id) {
                                GroupSummaryCard(group: group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: OutreachGroup.ID.self) { id in
            if let group = store.group(with: id) {
                GroupDetailView(group: group)
            }
        }
        .sheet(isPresented: $showingNewGroup) {
            NewGroupSheet()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your crew")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text("People you're rallying. Add neighbors, family, or coworkers — then rally them on issues you care about.")
                    .font(.system(size: 14))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                showingNewGroup = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(CivicTheme.cyan, in: Circle())
                    .shadow(color: CivicTheme.cyan.opacity(0.3), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        CivicGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Start your first crew", systemImage: "person.3.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CivicTheme.violet)
                Text("One person filing is a complaint. Ten people filing is a phone call from the chief of staff. A crew turns your civic action into a multiplier.")
                    .font(.system(size: 14))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineSpacing(3)

                Button {
                    showingNewGroup = true
                } label: {
                    HStack {
                        Text("Create a crew")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(CivicTheme.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                    .foregroundStyle(CivicTheme.cyan)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct GroupSummaryCard: View {
    let group: OutreachGroup

    var body: some View {
        CivicGlassCard {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                        .fill(CivicTheme.violet.opacity(0.15))
                    Text(group.emoji)
                        .font(.system(size: 26))
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Text("\(group.members.count) member\(group.members.count == 1 ? "" : "s") · \(group.totalRallies) rall\(group.totalRallies == 1 ? "y" : "ies") sent")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
        }
    }
}

private struct NewGroupSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var emoji: String = "✊"
    @FocusState private var nameFocused: Bool

    private let emojiOptions = ["✊", "🏠", "🚊", "🌳", "🏫", "💧", "🛡️", "💸", "📣", "🤝"]

    var body: some View {
        ZStack {
            CivicTheme.screenBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("New crew")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .textCase(.uppercase)
                    TextField("Tulpehocken Block", text: $name)
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
                    Text("Vibe")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .textCase(.uppercase)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(emojiOptions, id: \.self) { e in
                            Button {
                                emoji = e
                            } label: {
                                Text(e)
                                    .font(.system(size: 24))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(emoji == e ? CivicTheme.violet.opacity(0.18) : CivicTheme.panel, in: RoundedRectangle(cornerRadius: CivicTheme.mediumRadius))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CivicTheme.mediumRadius)
                                            .stroke(emoji == e ? CivicTheme.violet : CivicTheme.hairline, lineWidth: emoji == e ? 1.5 : 1)
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
                    store.addGroup(OutreachGroup(name: trimmed, emoji: emoji))
                    dismiss()
                } label: {
                    HStack {
                        Text("Create crew")
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
        .presentationDetents([.medium])
        .onAppear { nameFocused = true }
    }
}

#Preview {
    NavigationStack {
        GroupsListView()
            .environment(CivicOSStore())
    }
}
