import CryptoKit
import DeckKit
import Foundation
import Network

/// A key the TLS handshake will accept, and the identity that selects it.
struct PresharedKey: Hashable, Sendable {
    var identity: String
    var key: Data
}

/// Builds the Network.framework parameters both ends use (FR-3).
///
/// **Why pre-shared keys rather than certificates.** The PRD describes pinning the
/// agent's public key. Doing that literally means generating a self-signed X.509
/// identity at runtime, and neither macOS nor iOS offers a public API to create a
/// certificate — it would mean hand-assembling DER and signing it with `SecKey`. TLS-PSK
/// reaches the same guarantee by a supported route: the pairing connection is
/// authenticated by a key derived from the six-digit PIN, and every connection after it
/// by a 256-bit secret the agent mints at pairing. A machine that doesn't hold the
/// secret cannot complete the handshake at all, which is what FR-3 asks for — a
/// different Mac advertising the same name is not merely rejected, it is unable to
/// connect.
///
/// `DeviceIdentity.publicKeyHash` accordingly carries an HMAC fingerprint of the
/// agent's long-term secret rather than a public-key hash. It is safe to display and
/// compare, and it changes when the agent is reinstalled.
enum DeckTransport {
    /// The key that authenticates a pairing connection, derived from the PIN on both
    /// sides. Salted with the device ID so a PIN captured near one Mac is worthless
    /// against another.
    static func pairingKey(pin: PairingPIN, deviceID: String) -> Data {
        let key = SymmetricKey(data: Data(pin.digits.utf8))
        let message = Data("\(DeckService.pairingKeyContext):\(deviceID)".utf8)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
    }

    /// Client-side parameters: one key, one identity.
    static func parameters(key: PresharedKey) -> NWParameters {
        parameters(keys: [key])
    }

    /// Listener-side parameters.
    ///
    /// Several keys are registered at once — the current PIN key plus one per paired
    /// phone — and the client's PSK identity selects which one the handshake uses. That
    /// is what lets a paired phone reconnect silently while an unpaired one can still
    /// reach the pairing channel.
    static func parameters(keys: [PresharedKey]) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        for key in keys {
            sec_protocol_options_add_pre_shared_key(
                tlsOptions.securityProtocolOptions,
                dispatchData(key.key),
                dispatchData(Data(key.identity.utf8))
            )
        }
        sec_protocol_options_append_tls_ciphersuite(
            tlsOptions.securityProtocolOptions,
            tls_ciphersuite_t.AES_128_GCM_SHA256
        )

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        // A tap should feel instant, so the transport notices a dead peer quickly
        // rather than waiting out the default TCP timeout (FR-4).
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2
        tcpOptions.keepaliveInterval = 2
        tcpOptions.keepaliveCount = 3

        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        // Local network only: peer-to-peer transport is an explicit non-goal for v1.
        parameters.includePeerToPeer = false
        return parameters
    }

    /// `DispatchData` copies the bytes it is given, so the buffer does not have to
    /// outlive this call.
    private static func dispatchData(_ data: Data) -> __DispatchData {
        data.withUnsafeBytes { DispatchData(bytes: $0) as __DispatchData }
    }
}
