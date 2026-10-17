import Foundation

/// A single comment on a Square post. Local-first — lives in UserDefaults
/// alongside the post it belongs to.
struct CivicComment: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    let postID: SocialPost.ID
    /// "You" for the local user; later this can become a real handle when
    /// Square goes networked.
    var authorName: String
    var authorHandle: String
    var authorEmoji: String
    var body: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        postID: SocialPost.ID,
        authorName: String,
        authorHandle: String,
        authorEmoji: String,
        body: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.postID = postID
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.authorEmoji = authorEmoji
        self.body = body
        self.createdAt = createdAt
    }
}
