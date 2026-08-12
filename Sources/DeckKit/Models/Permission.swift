import Foundation

/// The three permissions NosoDeck ever asks for. Each is asked only behind the
/// pre-prompt card — *why · what breaks without it · the degraded path* — shown before
/// the system dialog (FR-24).
public enum PermissionKind: String, Codable, Sendable, CaseIterable {
    /// Reaching the Mac at all. The one permission with no degraded path.
    case localNetwork
    /// Apple Events, for listing and running Shortcuts (FR-13).
    case automation
    /// Synthetic paste for emoji insertion (FR-15).
    case accessibility

    /// What still works when the user says no. `nil` means the feature is impossible
    /// without the grant — true only for local network.
    public var degradedPath: String? {
        switch self {
        case .localNetwork:
            return nil
        case .automation:
            return "The Shortcuts tab is hidden. App and website tiles keep working."
        case .accessibility:
            return "Emoji are copied to the clipboard instead of typed, with a notification on the Mac."
        }
    }

    /// Whether v1 is usable at all without this grant.
    public var isRequired: Bool { degradedPath == nil }
}

public enum PermissionStatus: String, Codable, Sendable, CaseIterable {
    case notDetermined
    case granted
    case denied
}

/// The `permissions` slice of the app's state model.
///
/// Stored as three named fields rather than a dictionary keyed by `PermissionKind`:
/// `JSONEncoder` only writes a dictionary as a JSON object when its key is `String` or
/// `Int`, so an enum-keyed dictionary would silently serialize as a flat array.
public struct PermissionState: Codable, Hashable, Sendable {
    public var localNetwork: PermissionStatus
    public var automation: PermissionStatus
    public var accessibility: PermissionStatus

    public init(
        localNetwork: PermissionStatus = .notDetermined,
        automation: PermissionStatus = .notDetermined,
        accessibility: PermissionStatus = .notDetermined
    ) {
        self.localNetwork = localNetwork
        self.automation = automation
        self.accessibility = accessibility
    }

    public subscript(kind: PermissionKind) -> PermissionStatus {
        get {
            switch kind {
            case .localNetwork: return localNetwork
            case .automation: return automation
            case .accessibility: return accessibility
            }
        }
        set {
            switch kind {
            case .localNetwork: localNetwork = newValue
            case .automation: automation = newValue
            case .accessibility: accessibility = newValue
            }
        }
    }

    public var grantedCount: Int {
        PermissionKind.allCases.filter { self[$0] == .granted }.count
    }

    /// The "2 of 3 granted" row in Settings (design S7).
    public var summary: String {
        "\(grantedCount) of \(PermissionKind.allCases.count) granted"
    }
}
