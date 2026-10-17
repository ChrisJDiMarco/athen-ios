import Foundation

/// Compile-time flags for features that are scaffolded but not production-ready.
///
/// Set to `true` to show them in the UI during development. All consumers
/// must check the flag before rendering UI for the feature, so flipping it
/// here cleanly enables/disables every surface that touches that feature.
///
/// Keep this file tiny — when a feature graduates to production, delete the
/// flag and remove the call-site checks. Don't let dead flags pile up.
enum BetaFeatures {
    /// Ballot Photo Scanner — OCR pipeline scaffolded but the Vision wiring
    /// to per-contest brief lookup is incomplete. Hide until v1.1.
    static let ballotScanner: Bool = false

    /// Group Letters (coordinated multi-signer filings) — model + sheet exist,
    /// but the delivery pipeline shares the filings backend which is itself
    /// not sending until Postmark is wired. Hide until filings ship.
    static let groupLetters: Bool = false

    /// Outreach Groups (curated lists of contacts) — usable for personal
    /// organizing but the bulk-send UX is incomplete. Hide top-level entry
    /// while filings are still recorded-local.
    static let outreachGroups: Bool = false

    /// Athen Pro — subscription tier scaffolding. UX is wired (upgrade card,
    /// gated feature placeholders) but StoreKit purchase flow isn't. Showing
    /// the upgrade prompt in v1 sets up the path for v1.1 monetization
    /// without making users feel ambushed by paywalls.
    static let athenProPromptVisible: Bool = true

    /// When the user has actually purchased Pro. Wire this to the StoreKit
    /// subscription receipt once that's in place. Today it's permanently
    /// false — the upgrade card always shows.
    static let athenProActive: Bool = false
}
