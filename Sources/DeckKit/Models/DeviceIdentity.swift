import Foundation

/// A Mac as the phone knows it.
///
/// `publicKeyHash` is the part that matters for security: pairing pins it, and every
/// later connection is checked against it. A machine that reinstalls the agent gets a
/// new key and is treated as a stranger, which is exactly the FR-3 requirement that a
/// different machine advertising the same name is never silently trusted.
public struct DeviceIdentity: Identifiable, Codable, Hashable, Sendable {
    /// Stable per-installation identifier advertised alongside the Bonjour service.
    public var deviceID: String
    /// The Mac's user-visible name, e.g. "Nora's MacBook Pro". Display only — never
    /// used to decide trust.
    public var name: String
    /// Hash of the agent's TLS public key, pinned at pairing time.
    public var publicKeyHash: String

    public init(deviceID: String, name: String, publicKeyHash: String) {
        self.deviceID = deviceID
        self.name = name
        self.publicKeyHash = publicKeyHash
    }

    public var id: String { deviceID }
}
