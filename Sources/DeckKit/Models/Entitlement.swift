import Foundation

/// What the user has paid for. Premium is strictly additive — it never takes away
/// something the free tier had (FR-17).
public enum Entitlement: String, Codable, Sendable, CaseIterable {
    case free
    case premium

    /// D16: two pages free, eight with premium.
    public var maxPages: Int {
        switch self {
        case .free: return 2
        case .premium: return 8
        }
    }

    /// FR-16: free users see a locked teaser where the recents column would be — a
    /// teaser that opens the paywall, never a dead tap.
    public var unlocksRecentsColumn: Bool { self == .premium }

    /// FR-17: icon themes are premium.
    public var unlocksThemes: Bool { self == .premium }
}
