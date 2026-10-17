import SwiftUI

// MARK: - Hashtag + @mention parsing

/// Lightweight tokenizer that splits a post body into plain runs, @handles,
/// and #hashtags. Keeps the parser deterministic — no regex backtracking —
/// because we re-render on every keystroke in the composer preview.
enum SquareToken: Hashable {
    case text(String)
    case mention(String)  // includes leading @
    case hashtag(String)  // includes leading #
}

enum SquareTokenizer {
    static func tokenize(_ body: String) -> [SquareToken] {
        var out: [SquareToken] = []
        var buffer = ""
        var i = body.startIndex
        while i < body.endIndex {
            let ch = body[i]
            if ch == "@" || ch == "#" {
                if !buffer.isEmpty {
                    out.append(.text(buffer))
                    buffer = ""
                }
                var token = String(ch)
                var j = body.index(after: i)
                while j < body.endIndex, isMentionChar(body[j]) {
                    token.append(body[j])
                    j = body.index(after: j)
                }
                if token.count > 1 {
                    out.append(ch == "@" ? .mention(token) : .hashtag(token))
                    i = j
                    continue
                } else {
                    buffer.append(ch)
                }
            } else {
                buffer.append(ch)
            }
            i = body.index(after: i)
        }
        if !buffer.isEmpty { out.append(.text(buffer)) }
        return out
    }

    private static func isMentionChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "."
    }

    static func hashtags(in body: String) -> [String] {
        tokenize(body).compactMap {
            if case .hashtag(let h) = $0 { return h.lowercased() }
            return nil
        }
    }

    static func mentions(in body: String) -> [String] {
        tokenize(body).compactMap {
            if case .mention(let m) = $0 { return m }
            return nil
        }
    }
}

/// SwiftUI view that renders a post body with #hashtags and @mentions
/// styled as tappable callbacks. Used in post cards + thread view.
struct RichPostBody: View {
    let text: String
    var hashtagTint: Color = CivicTheme.cyan
    var mentionTint: Color = CivicTheme.violet
    var onHashtag: ((String) -> Void)? = nil
    var onMention: ((String) -> Void)? = nil

    init(
        body: String,
        hashtagTint: Color = CivicTheme.cyan,
        mentionTint: Color = CivicTheme.violet,
        onHashtag: ((String) -> Void)? = nil,
        onMention: ((String) -> Void)? = nil,
    ) {
        self.text = body
        self.hashtagTint = hashtagTint
        self.mentionTint = mentionTint
        self.onHashtag = onHashtag
        self.onMention = onMention
    }

    var body: some View {
        if onHashtag == nil && onMention == nil {
            attributedView
        } else {
            // When taps are wired, fall back to a flow layout of buttons so
            // each token has its own hit area. We don't get inline wrapping
            // but it's the right trade-off for a tappable feed.
            FlowingTokens(
                tokens: SquareTokenizer.tokenize(text),
                hashtagTint: hashtagTint,
                mentionTint: mentionTint,
                onHashtag: onHashtag,
                onMention: onMention,
            )
        }
    }

    private var attributedView: some View {
        let tokens = SquareTokenizer.tokenize(text)
        var attributed = AttributedString()
        for token in tokens {
            switch token {
            case .text(let s):
                attributed.append(AttributedString(s))
            case .mention(let m):
                var part = AttributedString(m)
                part.foregroundColor = mentionTint
                part.font = .system(size: 15, weight: .semibold)
                attributed.append(part)
            case .hashtag(let h):
                var part = AttributedString(h)
                part.foregroundColor = hashtagTint
                part.font = .system(size: 15, weight: .semibold)
                attributed.append(part)
            }
        }
        return Text(attributed)
            .environment(\.openURL, OpenURLAction { _ in .handled })
    }
}

/// Lightweight flow layout for tokens — wraps to the next line when an item
/// overflows. Less pretty than NSAttributedString tap handling but works.
private struct FlowingTokens: View {
    let tokens: [SquareToken]
    let hashtagTint: Color
    let mentionTint: Color
    let onHashtag: ((String) -> Void)?
    let onMention: ((String) -> Void)?

    var body: some View {
        // Word-split text tokens so they wrap naturally in the flow.
        let items: [Item] = tokens.flatMap { token -> [Item] in
            switch token {
            case .text(let s):
                return s
                    .split(separator: " ", omittingEmptySubsequences: false)
                    .map { Item.word(String($0)) }
            case .mention(let m): return [.mention(m)]
            case .hashtag(let h): return [.hashtag(h)]
            }
        }
        FlowLayout(spacing: 4, lineSpacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                switch item {
                case .word(let w):
                    Text(w + " ")
                        .font(.system(size: 15))
                        .foregroundStyle(CivicTheme.ink)
                case .mention(let m):
                    Button { onMention?(m) } label: {
                        Text(m + " ")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(mentionTint)
                    }
                    .buttonStyle(.plain)
                case .hashtag(let h):
                    Button { onHashtag?(h) } label: {
                        Text(h + " ")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(hashtagTint)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    enum Item: Hashable {
        case word(String)
        case mention(String)
        case hashtag(String)
    }
}

// Note: FlowLayout is defined in ProfileView.swift and reused here.

// MARK: - Trending hashtag strip

/// Picks the top 3-5 hashtags from the visible post window and surfaces
/// them as tappable chips above the feed.
struct TrendingHashtagStrip: View {
    let posts: [SocialPost]
    let activeHashtag: String?
    let onTap: (String?) -> Void

    var body: some View {
        let trending = compute()
        if trending.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CivicTheme.red)
                    Text("TRENDING")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(CivicTheme.mutedInk)
                    Spacer()
                    if activeHashtag != nil {
                        Button {
                            Haptics.selection()
                            onTap(nil)
                        } label: {
                            Text("Clear")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(CivicTheme.cyan)
                        }
                        .buttonStyle(.plain)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(trending, id: \.tag) { hit in
                            let active = activeHashtag == hit.tag
                            Button {
                                Haptics.selection()
                                onTap(active ? nil : hit.tag)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(hit.tag)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(active ? .white : CivicTheme.ink)
                                    Text("\(hit.count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(active ? .white.opacity(0.85) : CivicTheme.quietInk)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(active ? CivicTheme.red : CivicTheme.red.opacity(0.10), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private func compute() -> [TrendingHit] {
        var bucket: [String: Int] = [:]
        for post in posts {
            for tag in SquareTokenizer.hashtags(in: post.body) {
                bucket[tag, default: 0] += 1
            }
        }
        return bucket
            .map { TrendingHit(tag: $0.key, count: $0.value) }
            .sorted { ($0.count, $0.tag) > ($1.count, $1.tag) }
            .prefix(5)
            .map { $0 }
    }

    struct TrendingHit {
        let tag: String
        let count: Int
    }
}

// MARK: - Inline composer card

/// "What's on your mind?" tap target that lives at the top of the feed.
/// Functions as a tap-to-open shortcut into the full composer sheet.
struct InlineComposerCard: View {
    let avatarEmoji: String
    let placeholder: String
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            Haptics.selection()
            onTap()
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(CivicTheme.violet.opacity(0.14))
                    Text(avatarEmoji)
                        .font(.system(size: 18))
                }
                .frame(width: 36, height: 36)
                Text(placeholder)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CivicTheme.quietInk)
                Spacer()
                Image(systemName: "photo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
                Image(systemName: "chart.bar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CivicTheme.mutedInk)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compose a new post")
    }
}

// MARK: - Author profile sheet

/// Modal listing every post by one author handle. Tap a handle anywhere in
/// Square → this opens. Mute-author + report-author live in the toolbar
/// for parity with the contextual menus.
struct AuthorProfileSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let handle: String

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 12) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        ForEach(authoredPosts) { post in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: post.kind.systemImage)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(post.kind.tint)
                                    Text(post.kind.label.uppercased())
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(0.5)
                                        .foregroundStyle(post.kind.tint)
                                    Spacer()
                                    Text(post.createdAt, style: .relative)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(CivicTheme.quietInk)
                                }
                                Text(post.body)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(CivicTheme.ink)
                                    .lineLimit(4)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
                            .padding(.horizontal, 20)
                        }
                        if authoredPosts.isEmpty {
                            Text("No posts from \(handle) yet.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CivicTheme.mutedInk)
                                .padding(.top, 24)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(handle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CivicTheme.cyan)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            store.blockAuthor(handle)
                            Haptics.impact(.medium)
                            dismiss()
                        } label: {
                            Label("Block \(handle)", systemImage: "hand.raised.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(CivicTheme.violet.opacity(0.18))
                Text(authoredPosts.first?.authorEmoji ?? "👤")
                    .font(.system(size: 26))
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(authoredPosts.first?.authorName ?? handle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CivicTheme.ink)
                Text(handle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CivicTheme.mutedInk)
                Text("\(authoredPosts.count) post\(authoredPosts.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            Spacer()
        }
        .padding(14)
        .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CivicTheme.hairline, lineWidth: 1))
    }

    private var authoredPosts: [SocialPost] {
        store.socialPosts
            .filter { $0.authorHandle == handle }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - Event RSVP row

struct EventRSVPRow: View {
    @Environment(CivicOSStore.self) private var store
    let post: SocialPost

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let date = post.eventDate {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CivicTheme.amber)
                    Text(date, format: .dateTime.weekday().month().day().hour().minute())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CivicTheme.ink)
                    Spacer()
                    Text("\(post.eventRSVPs.going) going · \(post.eventRSVPs.interested) interested")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CivicTheme.quietInk)
                }
            }
            HStack(spacing: 6) {
                ForEach(EventRSVPKind.allCases) { kind in
                    let active = post.myRsvp == kind
                    Button {
                        Haptics.selection()
                        store.setRSVP(active ? nil : kind, on: post.id)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: kind.systemImage)
                                .font(.system(size: 10, weight: .bold))
                            Text(kind.label)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(active ? .white : kind.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(active ? kind.tint : kind.tint.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(kind.label) — \(post.eventRSVPs.count(kind)) so far")
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Poll card

struct PollCard: View {
    @Environment(CivicOSStore.self) private var store
    let post: SocialPost

    var body: some View {
        if let options = post.pollOptions, !options.isEmpty {
            let total = options.reduce(0) { $0 + $1.voteCount }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(options) { option in
                    let isPicked = post.myPollVote == option.id
                    let percent = total == 0 ? 0 : Double(option.voteCount) / Double(total)
                    Button {
                        Haptics.selection()
                        store.voteOnPoll(option.id, on: post.id)
                    } label: {
                        ZStack(alignment: .leading) {
                            GeometryReader { proxy in
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(CivicTheme.violet.opacity(isPicked ? 0.22 : 0.10))
                                    .frame(width: max(0, proxy.size.width * percent))
                            }
                            HStack {
                                Image(systemName: isPicked ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(isPicked ? CivicTheme.violet : CivicTheme.quietInk)
                                Text(option.text)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(CivicTheme.ink)
                                Spacer()
                                if total > 0 {
                                    Text("\(Int((percent * 100).rounded()))%")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(CivicTheme.mutedInk)
                                        .monospacedDigit()
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                        .frame(height: 36)
                        .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isPicked ? CivicTheme.violet : CivicTheme.hairline, lineWidth: isPicked ? 1.5 : 1),
                        )
                    }
                    .buttonStyle(.plain)
                }
                Text("\(total) vote\(total == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CivicTheme.quietInk)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Repost preview card

struct RepostPreview: View {
    @Environment(CivicOSStore.self) private var store
    let originalID: SocialPost.ID

    var body: some View {
        if let original = store.post(withID: originalID) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CivicTheme.violet)
                    Text("Reposted from \(original.authorHandle)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CivicTheme.mutedInk)
                    Spacer()
                    Text(original.createdAt, style: .relative)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CivicTheme.quietInk)
                }
                Text(original.body)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CivicTheme.ink)
                    .lineLimit(4)
            }
            .padding(12)
            .background(CivicTheme.panelElevated, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(CivicTheme.hairline, lineWidth: 1))
        } else {
            Text("Original post is unavailable")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CivicTheme.quietInk)
                .italic()
        }
    }
}

// MARK: - Repost composer sheet

struct RepostComposerSheet: View {
    @Environment(CivicOSStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let originalID: SocialPost.ID
    @State private var commentary: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                CivicTheme.screenBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TextEditor(text: $commentary)
                            .font(.system(size: 16))
                            .frame(minHeight: 110)
                            .padding(10)
                            .background(CivicTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CivicTheme.hairline, lineWidth: 1))
                            .overlay(alignment: .topLeading) {
                                if commentary.isEmpty {
                                    Text("Add your take…")
                                        .font(.system(size: 16))
                                        .foregroundStyle(CivicTheme.quietInk)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 18)
                                        .allowsHitTesting(false)
                                }
                            }

                        RepostPreview(originalID: originalID)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Repost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Repost") {
                        _ = store.repostPost(originalID, commentary: commentary.trimmingCharacters(in: .whitespacesAndNewlines))
                        Haptics.success()
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(CivicTheme.violet)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Pinned badge

struct PinnedBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "pin.fill")
                .font(.system(size: 9, weight: .bold))
            Text("PINNED")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
        }
        .foregroundStyle(CivicTheme.amber)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(CivicTheme.amber.opacity(0.14), in: Capsule())
    }
}
