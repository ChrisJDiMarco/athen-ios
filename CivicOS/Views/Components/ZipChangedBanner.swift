import SwiftUI

/// Soft banner that appears on every primary tab when the user has changed
/// their ZIP. Reminds them that data for THIS surface is auto-refreshing,
/// and gives them a tap-target to acknowledge once they've seen fresh data.
struct ZipChangedBanner: View {
    @Environment(CivicOSStore.self) private var store
    /// Lets each tab acknowledge independently (e.g., Brief acknowledges
    /// once briefDigest reloads; Voter on voterRail completion).
    var hasFreshData: Bool
    var onAcknowledge: () -> Void = {}

    var body: some View {
        if store.zipChangedNeedsRefresh {
            HStack(spacing: 10) {
                Image(systemName: hasFreshData ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(hasFreshData ? CivicTheme.green : CivicTheme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasFreshData ? "Updated for your new ZIP" : "Refreshing for your new ZIP…")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Text(hasFreshData ? "Tap to dismiss." : "Issues, briefs, voter info and sources are being re-pulled.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CivicTheme.mutedInk)
                        .lineLimit(2)
                }
                Spacer()
                if hasFreshData {
                    Button {
                        Haptics.selection()
                        onAcknowledge()
                        store.acknowledgeZipRefresh()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(CivicTheme.green)
                    }
                    .buttonStyle(.plain)
                } else {
                    ProgressView().scaleEffect(0.7).tint(CivicTheme.amber)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((hasFreshData ? CivicTheme.green : CivicTheme.amber).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke((hasFreshData ? CivicTheme.green : CivicTheme.amber).opacity(0.25), lineWidth: 1))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
