import SwiftUI

/// The "Hardware" palette, verbatim from `design/handoff/README.md`.
///
/// Three of these are semantic and never decorative: `mint` means state, `ochre` means
/// premium, `red` means destructive. Colour is also never the only cue for a state —
/// every place one of them appears, a shape or a word says the same thing.
///
/// v1 is dark-appearance only (light mode is undesigned), which is declared in the
/// generated Info.plist, so these are fixed values rather than an adaptive set.
enum DeckColor {
    private static var theme: DeckTheme { ThemeManager.shared.current }

    /// Outermost background, device bezel.
    static var void: Color { theme.void }
    /// App background.
    static var chassis: Color { theme.chassis }
    /// Cards, sheets.
    static var surface: Color { theme.surface }
    /// List rows, panels.
    static var surfaceRaised: Color { theme.surfaceRaised }

    /// Resting keycap fill, top and bottom of the gradient.
    static let keycapTop = Color(hex: 0x242424)
    static let keycapBottom = Color(hex: 0x191919)
    /// Frontmost keycap fill.
    static let keycapActiveTop = Color(hex: 0x2C2C2C)
    static let keycapActiveBottom = Color(hex: 0x202020)
    /// Pressed keycap fill.
    static let keycapPressed = Color(hex: 0x151515)

    static let stroke = Color(hex: 0x2F2F2F)
    static let strokeSubtle = Color(hex: 0x262626)

    static let ink = Color(hex: 0xE8E8E8)
    static let inkSecondary = Color(hex: 0xC8C8C8)
    static let inkMuted = Color(hex: 0x8A8A8A)
    static let inkFaint = Color(hex: 0x6A6A6A)

    /// State accent — running, frontmost, connected, primary confirm.
    static var mint: Color { theme.accent }
    /// Premium only — gates, upgrade CTA.
    static let ochre = Color(hex: 0xE8B94A)
    /// Destructive only — unpair, delete, disconnected banner.
    static let red = Color(hex: 0xEF4444)
    static let redInk = Color(hex: 0xFF8080)
    static let redBackground = Color(hex: 0x1E1414)

    /// Text on an accent fill.
    static var onMint: Color { theme.onAccent }
    /// Text on an ochre fill.
    static let onOchre = Color(hex: 0x1A1300)

    /// The keycap's structural highlight and drop, from the one shadow recipe.
    static let keycapHighlight = Color(hex: 0x3A3A3A)
    static let keycapDrop = Color(hex: 0x050505)
}

extension Color {
    /// Hex literals keep these readable against the handoff's colour table.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
