import UIKit

/// Distinct haptic patterns for different interaction types.
@MainActor
enum Haptics {
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    static func prepare() { rigid.prepare() }

    /// Tile tap — rigid keycap feel.
    static func tileTap() { rigid.impactOccurred() }

    /// Media control (play/pause, next, prev) — medium.
    static func mediaAction() { medium.impactOccurred() }

    /// Navigation action (back, forward, refresh) — light.
    static func navAction() { light.impactOccurred() }

    /// Scroll tick — soft, repeatable.
    static func scrollTick() { soft.impactOccurred(intensity: 0.4) }

    /// Volume change — selection tap.
    static func volumeTick() { selection.selectionChanged() }

    /// Key combo fired — heavy, deliberate.
    static func keyComboFired() { heavy.impactOccurred(intensity: 0.7) }

    /// Tile added to deck.
    static func tileAdded() { notification.notificationOccurred(.success) }

    /// Tile removed (before undo window).
    static func tileRemoved() { light.impactOccurred() }

    /// Edit mode entered/exited.
    static func editToggle() { selection.selectionChanged() }

    /// Pairing succeeded.
    static func pairingSucceeded() { notification.notificationOccurred(.success) }

    /// Wrong PIN.
    static func pairingFailed() { notification.notificationOccurred(.error) }

    /// Generic warning.
    static func warning() { notification.notificationOccurred(.warning) }
}
