import Foundation

/// SSE consumer for `/v1/refresh/stream`. Yields a typed event stream so the
/// UI can update a progress drawer as each connector reports in.
///
/// Server emits these event types:
///   - `started`      → `{startedAtISO}`
///   - `source_start` → `{id, name}`
///   - `source_done`  → full SourceReport (uses RefreshSourceReport model)
///   - `complete`     → full RefreshReport
///   - `error`        → `{message}`
///   - `heartbeat`    → ignored (keep-alive only)
enum RefreshStreamEvent: Equatable {
    case started(at: Date)
    case sourceStarted(id: String, name: String)
    case sourceDone(RefreshSourceReport)
    case complete(RefreshReport)
    case failed(message: String)
}

/// Errors the stream caller might surface.
enum RefreshStreamError: Error, LocalizedError {
    case notReachable
    case server(status: Int, message: String?)
    case decoding(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notReachable: "Backend isn't reachable."
        case .server(let s, let m): "Server error (\(s)): \(m ?? "no message")."
        case .decoding(let r): "Couldn't decode stream — \(r)."
        case .cancelled: "Refresh cancelled."
        }
    }
}

final class RefreshStreamService {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = AthenURLSession.shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Opens the SSE stream and yields each parsed event. The stream
    /// terminates after `complete` or `failed`. Cancel by cancelling the
    /// surrounding Task.
    func stream() -> AsyncThrowingStream<RefreshStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appendingPathComponent("v1/refresh/stream"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = "{}".data(using: .utf8)
                    request.timeoutInterval = 120

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw RefreshStreamError.notReachable
                    }
                    if !(200..<300).contains(http.statusCode) {
                        // Try to read the body for an error message.
                        var collected = Data()
                        for try await byte in bytes {
                            collected.append(byte)
                            if collected.count > 4096 { break }
                        }
                        let message = String(data: collected, encoding: .utf8)
                        throw RefreshStreamError.server(status: http.statusCode, message: message)
                    }

                    // Parse SSE line-by-line. SSE events are blocks of
                    // `event: x\ndata: y\n\n` separated by a blank line.
                    var currentEvent = ""
                    var currentData = ""
                    for try await line in bytes.lines {
                        if Task.isCancelled { throw RefreshStreamError.cancelled }
                        if line.isEmpty {
                            // Flush the accumulated event.
                            if !currentEvent.isEmpty {
                                if let parsed = parseEvent(name: currentEvent, payload: currentData) {
                                    continuation.yield(parsed)
                                    if case .complete = parsed { break }
                                    if case .failed = parsed { break }
                                }
                            }
                            currentEvent = ""
                            currentData = ""
                            continue
                        }
                        if line.hasPrefix("event:") {
                            currentEvent = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let chunk = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                            currentData = currentData.isEmpty ? chunk : currentData + "\n" + chunk
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func parseEvent(name: String, payload: String) -> RefreshStreamEvent? {
        guard let data = payload.data(using: .utf8) else { return nil }
        switch name {
        case "started":
            let date = decodeStartedAt(data) ?? .now
            return .started(at: date)
        case "source_start":
            struct Hit: Decodable { let id: String; let name: String }
            guard let hit = try? JSONDecoder().decode(Hit.self, from: data) else { return nil }
            return .sourceStarted(id: hit.id, name: hit.name)
        case "source_done":
            guard let rep = try? JSONDecoder().decode(RefreshSourceReport.self, from: data) else { return nil }
            return .sourceDone(rep)
        case "complete":
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = lenientISO8601()
            guard let report = try? decoder.decode(RefreshReport.self, from: data) else { return nil }
            return .complete(report)
        case "error":
            struct Err: Decodable { let message: String }
            let message = (try? JSONDecoder().decode(Err.self, from: data))?.message ?? "Refresh failed."
            return .failed(message: message)
        case "heartbeat":
            return nil
        default:
            return nil
        }
    }

    private func decodeStartedAt(_ data: Data) -> Date? {
        struct StartedPayload: Decodable { let startedAt: String }
        guard let payload = try? JSONDecoder().decode(StartedPayload.self, from: data) else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: payload.startedAt) ?? ISO8601DateFormatter().date(from: payload.startedAt)
    }

    /// Same lenient decoder the regular RefreshService uses — backend emits
    /// both fractional and non-fractional ISO-8601 timestamps.
    private func lenientISO8601() -> JSONDecoder.DateDecodingStrategy {
        .custom { dec in
            let raw = try dec.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }
            if let date = ISO8601DateFormatter().date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: try dec.singleValueContainer(), debugDescription: "Invalid ISO-8601: \(raw)")
        }
    }
}
