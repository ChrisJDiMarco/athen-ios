import Foundation

/// Shared URLSession that injects the per-install header on every request.
///
/// Behavior:
/// - Reads the install UUID once from UserDefaults (key: `athen.integration-entity-id.v1`)
///   and bakes it into `URLSessionConfiguration.httpAdditionalHeaders`.
/// - Every request originating from this session gets `X-Athen-Install: <uuid>`.
/// - All Athen HTTP services use this instead of `URLSession.shared` so the
///   header is always present without each service having to opt in.
///
/// If the install ID changes (very rare — only after manual UserDefaults wipe),
/// call `AthenURLSession.refresh()` to rebuild the session.
enum AthenURLSession {
    static let installHeaderName = "X-Athen-Install"
    private static let installDefaultsKey = "athen.integration-entity-id.v1"

    private static var cached: URLSession?

    static var shared: URLSession {
        if let cached { return cached }
        let session = build()
        cached = session
        return session
    }

    static func refresh() {
        cached = nil
    }

    private static func build() -> URLSession {
        let config = URLSessionConfiguration.default
        var headers = config.httpAdditionalHeaders ?? [:]
        if let install = currentInstallID() {
            headers[installHeaderName] = install
        }
        config.httpAdditionalHeaders = headers
        return URLSession(configuration: config)
    }

    private static func currentInstallID() -> String? {
        let raw = UserDefaults.standard.string(forKey: installDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }
}
