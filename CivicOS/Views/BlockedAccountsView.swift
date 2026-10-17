import SwiftUI

/// Settings panel listing all blocked authors with an Unblock action per row.
/// Required to satisfy Apple Guideline 1.2 — users must be able to undo a block.
struct BlockedAccountsView: View {
    @Environment(CivicOSStore.self) private var store

    private var sortedBlocked: [String] {
        store.blockedAuthors.sorted()
    }

    var body: some View {
        ZStack {
            CivicTheme.screenBackground.ignoresSafeArea()
            if sortedBlocked.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sortedBlocked, id: \.self) { handle in
                            row(handle: handle)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
            }
        }
        .navigationTitle("Blocked accounts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "hand.raised.slash.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(CivicTheme.cyan)
            Text("No one blocked")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Block an account from any post in Square. You'll be able to unblock them here.")
                .font(.system(size: 13))
                .foregroundStyle(CivicTheme.mutedInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 80)
    }

    private func row(handle: String) -> some View {
        HStack {
            Image(systemName: "person.crop.circle.badge.minus")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CivicTheme.red)
            Text(handle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CivicTheme.ink)
            Spacer()
            Button {
                Haptics.selection()
                store.unblockAuthor(handle)
            } label: {
                Text("Unblock")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CivicTheme.cyan)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(CivicTheme.cyan.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(CivicTheme.cyan.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
    }
}
