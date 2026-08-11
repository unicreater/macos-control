import Foundation

/// What the phone concluded about a Mac it just found.
public enum TrustDecision: Hashable, Sendable {
    /// Known device, key matches — connect straight through, no PIN (FR-2).
    case trusted
    /// Never paired with this device. Needs the PIN.
    case unknown
    /// Known device ID, *different* key. Never trusted silently: the user is shown the
    /// "identity changed" card and must re-pair deliberately (FR-3, design S3).
    case identityChanged(pinnedKeyHash: String, presentedKeyHash: String)
}

/// The set of Macs this phone trusts, keyed by device ID.
///
/// Pure data on purpose. Where it is *stored* is platform work — the Keychain, on both
/// sides — but what counts as trusted is logic, and logic belongs where it can be
/// tested without a device.
public struct TrustStore: Codable, Hashable, Sendable {
    private var pinnedKeyHashes: [String: String]

    public init(pinnedKeyHashes: [String: String] = [:]) {
        self.pinnedKeyHashes = pinnedKeyHashes
    }

    public func evaluate(_ identity: DeviceIdentity) -> TrustDecision {
        guard let pinned = pinnedKeyHashes[identity.deviceID] else { return .unknown }
        guard pinned == identity.publicKeyHash else {
            return .identityChanged(pinnedKeyHash: pinned, presentedKeyHash: identity.publicKeyHash)
        }
        return .trusted
    }

    public func isTrusted(_ identity: DeviceIdentity) -> Bool {
        evaluate(identity) == .trusted
    }

    /// Records trust. Called only after a correct PIN — never on a rejected attempt,
    /// so a wrong PIN leaves no trace (FR-2).
    public mutating func pin(_ identity: DeviceIdentity) {
        pinnedKeyHashes[identity.deviceID] = identity.publicKeyHash
    }

    /// Unpair (FR-5), and the first half of a re-pair after an identity change.
    @discardableResult
    public mutating func forget(deviceID: String) -> Bool {
        pinnedKeyHashes.removeValue(forKey: deviceID) != nil
    }

    public var pairedDeviceIDs: [String] { pinnedKeyHashes.keys.sorted() }
    public var isEmpty: Bool { pinnedKeyHashes.isEmpty }

    /// True when this phone has never paired with anything — what decides whether
    /// onboarding is shown at all (FR-22).
    public var hasNeverPaired: Bool { isEmpty }
}
