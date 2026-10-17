import SwiftUI

enum AppBrand {
    static let name = "Athen"
    static let tagline = "See what power is doing. Act for the public good."
    static let shortTagline = "Stay informed. Get help. Act together."
}

enum CivicTheme {
    // MARK: - Radii (more rounded, more friendly)
    static let cornerRadius: CGFloat = 22
    static let mediumRadius: CGFloat = 16
    static let smallRadius: CGFloat = 12

    // MARK: - Text
    static let ink = Color(red: 0.121, green: 0.141, blue: 0.176)        // #1F242D — warm near-black
    static let mutedInk = Color(red: 0.396, green: 0.431, blue: 0.482)   // #656E7B
    static let quietInk = Color(red: 0.612, green: 0.643, blue: 0.690)   // #9CA4B0

    // MARK: - Surfaces
    /// Main app canvas. A warm cream that's friendlier than pure white.
    static let canvas = Color(red: 0.976, green: 0.965, blue: 0.937)     // #F9F6EF
    /// Card surface. Pure white with a soft shadow.
    static let panel = Color.white
    /// Slightly inset surface (composer, inputs, soft tiles).
    static let panelElevated = Color(red: 0.957, green: 0.945, blue: 0.918) // #F4F1EA
    /// Thin border on light surfaces — barely visible.
    static let hairline = Color(red: 0.886, green: 0.871, blue: 0.835)   // #E2DED5

    // MARK: - Accents (Tailwind 500 family — friendly but credible)
    static let cyan = Color(red: 0.078, green: 0.722, blue: 0.651)       // #14B8A6 teal-500
    static let green = Color(red: 0.133, green: 0.773, blue: 0.369)      // #22C55E green-500
    static let amber = Color(red: 0.961, green: 0.620, blue: 0.043)      // #F59E0B amber-500
    static let red = Color(red: 0.937, green: 0.267, blue: 0.267)        // #EF4444 red-500
    static let violet = Color(red: 0.545, green: 0.361, blue: 0.965)     // #8B5CF6 violet-500

    // MARK: - Card elevation
    static let cardShadow = Color(red: 0.16, green: 0.18, blue: 0.22).opacity(0.07)
    static let cardShadowStrong = Color(red: 0.16, green: 0.18, blue: 0.22).opacity(0.10)

    // MARK: - Backgrounds
    static let screenBackground = LinearGradient(
        colors: [
            Color(red: 0.984, green: 0.973, blue: 0.945), // top
            Color(red: 0.961, green: 0.949, blue: 0.918)  // bottom
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Per-impact tinting
    static func impactColor(for level: ImpactLevel) -> Color {
        switch level {
        case .urgent:
            amber
        case .material:
            cyan
        case .watch:
            violet
        }
    }
}
