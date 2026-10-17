import Foundation

struct ChatMessage: Identifiable, Hashable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var content: String
    let createdAt: Date
    var isStreaming: Bool
    /// Tool invocations that fired during this assistant turn — e.g. a
    /// web_search the model called. Surfaced inline so the user can see
    /// what the AI looked up before synthesizing the answer.
    var toolCalls: [ChatToolCall]

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = .now,
        isStreaming: Bool = false,
        toolCalls: [ChatToolCall] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.toolCalls = toolCalls
    }
}

/// Record of one tool fire during an assistant turn. `summary` is the
/// short human-readable label set when the backend's runTool returns
/// (e.g. `philadelphia mayor 2026 — 8 results`).
struct ChatToolCall: Hashable, Codable {
    enum Status: String, Codable {
        case running
        case done
        case failed
    }
    let name: String           // e.g. "web_search"
    var status: Status
    var summary: String?
}

enum ChatStreamEvent {
    case delta(String)
    /// Model decided to call a tool — show a spinner / "Searching the web…".
    case toolStart(name: String)
    /// Tool finished — flip the indicator to a check + brief result label.
    case toolDone(name: String, summary: String)
    case done
    case error(String)
}
