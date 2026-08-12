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
    /// Outermost background, device bezel.
    static let void = Color(hex: 0x0A0A0A)
    /// App background.
    static let chassis = Color(hex: 0x111111)
    /// Cards, sheets.
    static let surface = Color(hex: 0x161616)
    /// List rows, panels.
    static let surfaceRaised = Color(hex: 0x1A1A1A)

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

    /// State only — running, frontmost, connected, primary confirm.
    static let mint = Color(hex: 0xA4D4C5)
    /// Premium only — gates, upgrade CTA.
    static let ochre = Color(hex: 0xE8B94A)
    /// Destructive only — unpair, delete, disconnected banner.
    static let red = Color(hex: 0xEF4444)
    static let redInk = Color(hex: 0xFF8080)
    static let redBackground = Color(hex: 0x1E1414)

    /// Text on a mint fill.
    static let onMint = Color(hex: 0x0A1A1A)
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
