import UIKit

/// Haptics, on exactly two events: a tile tap and pairing success (design handoff,
/// "Interactions").
///
/// The restraint is the design. A deck that buzzes at everything stops meaning anything,
/// so there is no API here for anything else.
@MainActor
enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()

    /// Call shortly before a tap is likely, so the engine is warm and the tap feels
    /// immediate rather than late.
    static func prepare() {
        impact.prepare()
    }

    /// A tile tap. Rigid, because the thing being pressed is meant to feel like a keycap.
    static func tileTap() {
        impact.impactOccurred()
    }

    static func pairingSucceeded() {
        notification.notificationOccurred(.success)
    }

    /// A wrong PIN. The design calls for an error haptic alongside the shake.
    static func pairingFailed() {
        notification.notificationOccurred(.error)
    }
}
