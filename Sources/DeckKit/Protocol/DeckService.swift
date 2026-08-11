import Foundation

/// Constants both ends must agree on exactly: the Bonjour service, its TXT keys, and
/// the labels that go into key derivation.
///
/// They live in DeckKit rather than in either app because a mismatch here doesn't fail
/// loudly — it just means the phone never finds the Mac, or the TLS handshake fails
/// with nothing useful to say about why.
public enum DeckService {
    /// FR-1: what the agent advertises and the phone browses for.
    public static let bonjourType = "_nosodeck._tcp"
    public static let bonjourDomain = "local."

    // MARK: - TXT record

    /// Stable per-installation ID of the Mac.
    public static let txtDeviceIDKey = "did"
    /// The Mac's display name, so the device list can label a row before connecting.
    public static let txtNameKey = "name"
    /// Wire protocol version, so an incompatible peer can be shown as such rather than
    /// failing mysteriously at handshake time.
    public static let txtProtocolVersionKey = "v"

    // MARK: - Transport security
    //
    // Both sides authenticate with a TLS pre-shared key. Pairing runs over a PSK
    // derived from the six-digit PIN, and everything after it over a long random
    // secret the agent hands out once pairing succeeds. The PSK identity tells the
    // agent which key to expect: the pairing key, or a specific phone's.

    /// PSK identity used for the pairing connection.
    public static let pairingKeyIdentity = "nosodeck-pairing"

    /// HMAC context for the PIN-derived pairing key.
    public static let pairingKeyContext = "nosodeck-pairing-v1"

    /// HMAC context for the fingerprint published in `DeviceIdentity.publicKeyHash`.
    /// Derived from the agent's long-term secret rather than being it, so the
    /// fingerprint can be shown, logged, and compared without leaking anything.
    public static let identityFingerprintContext = "nosodeck-identity-v1"

    /// Length of the per-phone session secret the agent generates at pairing.
    public static let sessionSecretByteCount = 32
}
