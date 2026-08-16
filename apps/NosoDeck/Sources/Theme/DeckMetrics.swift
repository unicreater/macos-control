import SwiftUI

/// Spacing, radii and the one shadow recipe (design handoff, "Space, radius, depth").
enum DeckSpace {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    /// The landscape safe-area inset. Nothing interactive sits inside it.
    static let safeInset: CGFloat = 34
}

enum DeckRadius {
    static let badge: CGFloat = 6
    static let control: CGFloat = 10
    /// The keycap.
    static let tile: CGFloat = 12
    static let card: CGFloat = 16
}

enum DeckGrid {
    /// Landscape: 4 columns × 2 rows. Portrait: 2 columns × 4 rows.
    /// Always 8 tiles max per page (D15).
    static func columns(isPortrait: Bool) -> Int { isPortrait ? 2 : 4 }
    static func rows(isPortrait: Bool) -> Int { isPortrait ? 4 : 2 }

    // Keep the old constants for backward compat
    static let columns = 4
    static let rows = 2
    static let gutter: CGFloat = 2
    static let topPadding: CGFloat = 16
    static let bottomPadding: CGFloat = 14
    static let recentsColumnWidth: CGFloat = 92
    static let recentsColumnGap: CGFloat = 14
}

/// Depth here is structural, not atmospheric — there are no soft ambient shadows
/// anywhere in this UI. Every keycap uses this one recipe:
/// `inset 0 1px 0 #3a3a3a, 0 3px 0 #050505`.
struct KeycapDepth: ViewModifier {
    var isPressed: Bool = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                // The inset highlight along the top edge.
                if !isPressed {
                    Rectangle()
                        .fill(DeckColor.keycapHighlight)
                        .frame(height: 1)
                        .padding(.horizontal, 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DeckRadius.tile, style: .continuous))
            .shadow(color: isPressed ? .clear : DeckColor.keycapDrop, radius: 0, x: 0, y: 3)
    }
}

extension View {
    func keycapDepth(isPressed: Bool = false) -> some View {
        modifier(KeycapDepth(isPressed: isPressed))
    }
}

/// Motion tier: subtle. 80–150ms tap feedback, ~200ms for state changes, and every
/// animation has a fade-only variant under Reduce Motion.
enum DeckMotion {
    static let tap = Animation.easeOut(duration: 0.1)
    static let stateChange = Animation.easeInOut(duration: 0.2)
    /// Exits are faster than entrances.
    static let exit = Animation.easeIn(duration: 0.12)
    /// Spinners appear only after this delay.
    static let spinnerDelay: Duration = .milliseconds(300)
}
