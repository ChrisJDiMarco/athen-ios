import SwiftUI

/// Full-screen comment thread for one Square post.
/// Header = the post itself (compact). Body = chronological comments.
/// Footer = inline composer.
struct PostThreadView: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let postID: SocialPost.ID
    @FocusState private var composerFocused: Bool
    @State private var draft: String = ""
    @State private var editingCommentID: CivicComment.ID?
    @State private var pendingDelete: CivicComment?
    @State private var bottomTrigger = 0

    private var post: SocialPost? {
        store.socialPosts.first { $0.id == postID }
    }

    private var comments: [CivicComment] {
        store.comments(for: postID)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                CivicTheme.screenBackground.ignoresSafeArea()

                if let post {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 14) {
                                ThreadPostCard(post: post)
                                threadHeader
                                if comments.isEmpty {
                                    emptyState
                                } else {
                                    LazyVStack(spacing: 10) {
                                        ForEach(comments) { comment in
                                            CommentRow(
                                                comment: comment,
                                                isMine: store.isMyComment(comment),
                                                onEdit: { startEditing(comment) },
                                                onDelete: { pendingDelete = comment }
                                            )
                                            .id(comment.id)
                                        }
                                    }
                                }
                                Color.clear.frame(height: 90).id("__bottom")
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 16)
                        }
                        .onChange(of: bottomTrigger) { _, _ in
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo("__bottom", anchor: .bottom)
                            }
                        }
                    }
                } else {
                    notFound
                }

                composer
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .confirmationDialog(
                "Delete this comment?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let c = pendingDelete {
                        store.deleteComment(c.id, on: postID)
                        Haptics.impact(.medium)
                    }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            }
        }
        .presentationDetents([.large])
    }

    private var threadHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.cyan)
            Text(comments.isEmpty ? "BE FIRST" : "\(comments.count) COMMENT\(comments.count == 1 ? "" : "S")")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CivicTheme.cyan)
                .tracking(0.5)
            Rectangle().fill(CivicTheme.cyan.opacity(0.22)).frame(height: 1)
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(CivicTheme.quietInk)
            Text("No comments yet")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("Be the first to add a take.")
                .font(.system(size: 12))
                .foregroundStyle(CivicTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var notFound: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(CivicTheme.quietInk)
            Text("This post no longer exists")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CivicTheme.ink)
            Text("It may have been deleted.")
                .font(.system(size: 12))
                .foregroundStyle(CivicTheme.mutedInk)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack {
                Circle().fill(CivicTheme.cyan.opacity(0.18))
                Text("🙂").font(.system(size: 18))
            }
            .frame(width: 36, height: 36)

            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(editingCommentID == nil ? "Add a comment…" : "Edit your comment…")
                        .font(.system(size: 14))
                        .foregroundStyle(CivicTheme.quietInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $draft)
                    .scrollContentBackground(.hidden)
                    .focused($composerFocused)
                    .font(.system(size: 14))
                    .foregroundStyle(CivicTheme.ink)
                    .frame(minHeight: 36, maxHeight: 130)
                    .tint(CivicTheme.cyan)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))

            Button {
                submit()
            } label: {
                Image(systemName: editingCommentID == nil ? "arrow.up" : "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(canSubmit ? CivicTheme.cyan : CivicTheme.quietInk, in: Circle())
                    .shadow(color: (canSubmit ? CivicTheme.cyan : CivicTheme.quietInk).opacity(0.25), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            CivicTheme.panel
                .overlay(Rectangle().fill(CivicTheme.hairline).frame(height: 1), alignment: .top)
        )
    }

    private var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let editingCommentID {
            store.editComment(editingCommentID, on: postID, body: text)
            Haptics.success()
        } else {
            store.addComment(to: postID, body: text)
            Haptics.success()
        }
        draft = ""
        editingCommentID = nil
        composerFocused = false
        bottomTrigger += 1
    }

    private func startEditing(_ comment: CivicComment) {
        editingCommentID = comment.id
        draft = comment.body
        composerFocused = true
    }
}

private struct ThreadPostCard: View {
    let post: SocialPost

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(post.kind.tint.opacity(0.16))
                    Text(post.authorEmoji).font(.system(size: 18))
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(post.authorName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CivicTheme.ink)
                        Text(post.authorHandle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CivicTheme.quietInk)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(post.locality)
                            .font(.system(size: 11, weight: .semibold))
                        Text("·").font(.system(size: 11, weight: .bold))
                        Text(post.createdAt.formattedShort)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(CivicTheme.mutedInk)
                }
                Spacer()
            }
            Text(post.body)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(CivicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let title = post.issueTitle {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.violet)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(CivicTheme.violet.opacity(0.10), in: Capsule())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CivicTheme.hairline, lineWidth: 1))
    }
}

private struct CommentRow: View {
    @Environment(CivicOSStore.self) private var store
    let comment: CivicComment
    let isMine: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showBlockConfirm: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(isMine ? CivicTheme.cyan.opacity(0.18) : CivicTheme.panelElevated)
                Text(comment.authorEmoji).font(.system(size: 14))
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CivicTheme.ink)
                    Text(comment.authorHandle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CivicTheme.quietInk)
                    Text("·").font(.system(size: 11, weight: .bold)).foregroundStyle(CivicTheme.quietInk)
                    Text(comment.createdAt.formattedShort)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CivicTheme.quietInk)
                }
                Text(comment.body)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(CivicTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Menu {
                if isMine {
                    Button {
                        Haptics.selection()
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        Haptics.impact(.light)
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } else {
                    Button(role: .destructive) {
                        Haptics.impact(.light)
                        store.reportComment(comment, reason: "Reported from thread")
                    } label: {
                        Label("Report comment", systemImage: "flag.fill")
                    }
                    Button(role: .destructive) {
                        Haptics.impact(.light)
                        showBlockConfirm = true
                    } label: {
                        Label("Block \(comment.authorHandle)", systemImage: "hand.raised.fill")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CivicTheme.quietInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
        .padding(12)
        .background(isMine ? CivicTheme.cyan.opacity(0.05) : CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isMine ? CivicTheme.cyan.opacity(0.22) : CivicTheme.hairline, lineWidth: 1))
        .confirmationDialog(
            "Block \(comment.authorHandle)?",
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                store.blockAuthor(comment.authorHandle)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see comments or posts from \(comment.authorHandle) again. You can unblock from Settings.")
        }
    }
}

private extension Date {
    var formattedShort: String {
        let interval = Date.now.timeIntervalSince(self)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604_800 { return "\(Int(interval / 86400))d" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}
