import SwiftUI

/// In-app notifications inbox — surfaces everything Athen has alerted the
/// user about even if the system banner was dismissed. Always in sync with
/// `store.inboxNotifications`.
struct NotificationsInboxView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.inboxNotifications.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Mark all read") { store.markAllInboxRead() }
                            .disabled(store.unreadInboxCount == 0)
                        Button("Clear inbox", role: .destructive) { store.clearInbox() }
                            .disabled(store.inboxNotifications.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(CivicTheme.quietInk)
            Text("No notifications yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CivicTheme.ink)
            Text("When Athen pings you about a vote, filing receipt, or petition delivery, it'll show up here.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CivicTheme.mutedInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(store.inboxNotifications) { entry in
                row(entry)
                    .listRowBackground(entry.isRead ? Color.clear : CivicTheme.cyan.opacity(0.06))
                    .listRowSeparatorTint(CivicTheme.hairline)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.markInboxRead(entry.id)
                    }
            }
        }
        .listStyle(.plain)
    }

    private func row(_ entry: AthenInboxNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint(for: entry.kind).opacity(0.18))
                Image(systemName: icon(for: entry.kind))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint(for: entry.kind))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CivicTheme.ink)
                    Spacer()
                    if let date = entry.scheduledAt {
                        Text(date, style: .relative)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CivicTheme.quietInk)
                            .monospacedDigit()
                    }
                }
                Text(entry.body)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                    .lineLimit(3)
            }
            if !entry.isRead {
                Circle()
                    .fill(CivicTheme.cyan)
                    .frame(width: 8, height: 8)
                    .padding(.top, 14)
            }
        }
        .padding(.vertical, 6)
    }

    private func icon(for kind: AthenInboxNotification.Kind) -> String {
        switch kind {
        case .deadline:          return "calendar.badge.exclamationmark"
        case .streak:            return "flame.fill"
        case .filingSent:        return "paperplane.fill"
        case .petitionDelivered: return "envelope.badge.shield.half.filled.fill"
        case .systemUpdate:      return "sparkles"
        }
    }

    private func tint(for kind: AthenInboxNotification.Kind) -> Color {
        switch kind {
        case .deadline:          return CivicTheme.amber
        case .streak:            return CivicTheme.red
        case .filingSent:        return CivicTheme.cyan
        case .petitionDelivered: return CivicTheme.violet
        case .systemUpdate:      return CivicTheme.green
        }
    }
}
