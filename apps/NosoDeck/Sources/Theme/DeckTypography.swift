import SwiftUI

/// Two families, one job each (design handoff). Mixing them inside a single element is
/// a violation, so every text style in the app comes from this list.
///
/// SF Mono is the machine voice — tile legends, status, page numbers, section labels —
/// always uppercase with positive tracking. SF Pro is the human voice: headings, body
/// copy, buttons, settings labels.
enum DeckFont {
    /// Inter 38–56 / 500 / −1 to −2.
    case display
    /// Inter 26–32 / 500 / −0.5 to −1.
    case title
    /// Serif headline for onboarding/PIN screens.
    case serifHeadline
    /// Inter 15–17 / 400.
    case body
    /// Inter 13–14 / 400.
    case bodySmall
    /// SF Mono 12 / +1, uppercase. The keycap legend.
    case legend
    /// SF Mono 11–13 / +1.5, uppercase. Status and section labels.
    case meta
    /// SF Mono 13, for the digits in the PIN cells and the clock.
    case monoDigits

    var size: CGFloat {
        switch self {
        case .display: return 38
        case .title: return 28
        case .serifHeadline: return 38
        case .body: return 16
        case .bodySmall: return 13
        case .legend: return 12
        case .meta: return 11
        case .monoDigits: return 13
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display, .title: return .medium
        case .serifHeadline: return .bold
        default: return .regular
        }
    }

    var design: Font.Design {
        switch self {
        case .legend, .meta, .monoDigits: return .monospaced
        case .serifHeadline: return .serif
        default: return .default
        }
    }

    var tracking: CGFloat {
        switch self {
        case .display: return -1
        case .title, .serifHeadline: return -0.5
        case .legend: return 1
        case .meta: return 1.5
        default: return 0
        }
    }

    /// The text style each role scales against, so Dynamic Type works throughout.
    var textStyle: Font.TextStyle {
        switch self {
        case .display, .serifHeadline: return .largeTitle
        case .title: return .title
        case .body: return .body
        case .bodySmall: return .footnote
        case .legend, .monoDigits: return .caption
        case .meta: return .caption2
        }
    }

    /// The machine voice is always uppercase.
    var isUppercased: Bool {
        switch self {
        case .legend, .meta: return true
        default: return false
        }
    }
}

private struct DeckFontModifier: ViewModifier {
    let role: DeckFont
    @ScaledMetric private var scale: CGFloat

    init(role: DeckFont) {
        self.role = role
        // Scales 1.0 against the role's text style, giving Dynamic Type support for
        // sizes the handoff specifies in points.
        _scale = ScaledMetric(wrappedValue: 1, relativeTo: role.textStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: role.size * scale, weight: role.weight, design: role.design))
            .tracking(role.tracking)
            .textCase(role.isUppercased ? .uppercase : nil)
    }
}

extension View {
    func deckFont(_ role: DeckFont) -> some View {
        modifier(DeckFontModifier(role: role))
    }
}
