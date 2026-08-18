import SwiftUI

struct DeckTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let isPremium: Bool

    // Backgrounds
    let void: Color
    let chassis: Color
    let surface: Color
    let surfaceRaised: Color

    // Accent
    let accent: Color
    let onAccent: Color

    // Mesh gradient background (nil = solid chassis)
    let meshColors: [Color]?

    static let all: [DeckTheme] = [midnight, aurora, ember, ocean, frost]

    // MARK: - Presets

    static let midnight = DeckTheme(
        id: "midnight", name: "Midnight", isPremium: false,
        void: Color(hex: 0x0A0A0A), chassis: Color(hex: 0x111111),
        surface: Color(hex: 0x161616), surfaceRaised: Color(hex: 0x1A1A1A),
        accent: Color(hex: 0xA4D4C5), onAccent: Color(hex: 0x0A1A1A),
        meshColors: nil
    )

    static let aurora = DeckTheme(
        id: "aurora", name: "Aurora", isPremium: false,
        void: Color(hex: 0x060818), chassis: Color(hex: 0x0A0E20),
        surface: Color(hex: 0x101630), surfaceRaised: Color(hex: 0x141A38),
        accent: Color(hex: 0x7DF9FF), onAccent: Color(hex: 0x0A1A1A),
        meshColors: [
            Color(hex: 0x0A0E20), Color(hex: 0x1A0A30), Color(hex: 0x0A1830),
            Color(hex: 0x2D1B69), Color(hex: 0x0E4D64), Color(hex: 0x1A0A30),
            Color(hex: 0x0A1830), Color(hex: 0x0E3A5A), Color(hex: 0x1A0E40),
        ]
    )

    static let ember = DeckTheme(
        id: "ember", name: "Ember", isPremium: false,
        void: Color(hex: 0x120808), chassis: Color(hex: 0x1A0E0A),
        surface: Color(hex: 0x201410), surfaceRaised: Color(hex: 0x261812),
        accent: Color(hex: 0xF59E0B), onAccent: Color(hex: 0x1A0E00),
        meshColors: [
            Color(hex: 0x200A06), Color(hex: 0x2A0E08), Color(hex: 0x351A0C),
            Color(hex: 0x480E1A), Color(hex: 0x601818), Color(hex: 0x6A3010),
            Color(hex: 0x6A2416), Color(hex: 0x704020), Color(hex: 0x7A5028),
        ]
    )

    static let ocean = DeckTheme(
        id: "ocean", name: "Ocean", isPremium: false,
        void: Color(hex: 0x06101A), chassis: Color(hex: 0x0A1420),
        surface: Color(hex: 0x0E1A2A), surfaceRaised: Color(hex: 0x121E30),
        accent: Color(hex: 0x60A5FA), onAccent: Color(hex: 0x0A1020),
        meshColors: [
            Color(hex: 0x080C18), Color(hex: 0x0A1028), Color(hex: 0x060A14),
            Color(hex: 0x0E3060), Color(hex: 0x0C2848), Color(hex: 0x081A30),
            Color(hex: 0x0A2028), Color(hex: 0x0E3848), Color(hex: 0x0A1820),
        ]
    )

    static let frost = DeckTheme(
        id: "frost", name: "Frost", isPremium: false,
        void: Color(hex: 0x0E1218), chassis: Color(hex: 0x141820),
        surface: Color(hex: 0x1A1E28), surfaceRaised: Color(hex: 0x1E2230),
        accent: Color(hex: 0x818CF8), onAccent: Color(hex: 0x0E0E1A),
        meshColors: [
            Color(hex: 0x141820), Color(hex: 0x1A1830), Color(hex: 0x141A28),
            Color(hex: 0x2A2848), Color(hex: 0x1E2440), Color(hex: 0x1A1E30),
            Color(hex: 0x141820), Color(hex: 0x222838), Color(hex: 0x1A1E2A),
        ]
    )
}

/// Manages the active theme. Observable so SwiftUI updates everywhere.
/// nonisolated(unsafe) on shared so DeckColor can read it from any context.
@MainActor
@Observable
final class ThemeManager {
    nonisolated(unsafe) static let shared = ThemeManager()

    private static let storageKey = "com.noso.nosodeck.theme"

    nonisolated(unsafe) var current: DeckTheme {
        didSet {
            UserDefaults.standard.set(current.id, forKey: Self.storageKey)
        }
    }

    private init() {
        let savedID = UserDefaults.standard.string(forKey: Self.storageKey) ?? "midnight"
        self.current = DeckTheme.all.first { $0.id == savedID } ?? .midnight
    }
}
