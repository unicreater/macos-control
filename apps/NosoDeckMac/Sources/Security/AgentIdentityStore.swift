import CryptoKit
import DeckKit
import Foundation

/// The agent's own identity, and the set of phones it trusts.
///
/// Both are Keychain-backed and survive relaunch, which is what makes FR-2's "force-quit
/// and relaunch both apps, reconnect with no PIN" hold. A reinstall loses the Keychain
/// items and therefore the identity, which is exactly the FR-3 case the phone must
/// notice rather than silently accept.
struct AgentIdentityStore {
    private static let deviceIDAccount = "agent.deviceID"
    private static let secretAccount = "agent.secret"
    private static let pairedPrefix = "phone."

    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    // MARK: - This Mac

    /// Stable ID for this installation, minted on first launch.
    var deviceID: String {
        if let data = keychain.data(forAccount: Self.deviceIDAccount),
           let existing = String(data: data, encoding: .utf8), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        keychain.set(Data(fresh.utf8), forAccount: Self.deviceIDAccount)
        return fresh
    }

    /// The agent's long-term secret. Never leaves the Mac — only the fingerprint
    /// derived from it does.
    var secret: Data {
        if let existing = keychain.data(forAccount: Self.secretAccount),
           existing.count == DeckService.sessionSecretByteCount {
            return existing
        }
        let fresh = Self.randomSecret()
        keychain.set(fresh, forAccount: Self.secretAccount)
        return fresh
    }

    /// A publishable stand-in for the secret: same value for the life of an install,
    /// different after a reinstall, and useless to an attacker who learns it.
    var fingerprint: String {
        let key = SymmetricKey(data: secret)
        let code = HMAC<SHA256>.authenticationCode(
            for: Data(DeckService.identityFingerprintContext.utf8),
            using: key
        )
        return Data(code).map { String(format: "%02x", $0) }.joined()
    }

    func identity(name: String) -> DeviceIdentity {
        DeviceIdentity(deviceID: deviceID, name: name, publicKeyHash: fingerprint)
    }

    // MARK: - Paired phones

    /// Phone device ID → the session secret that phone authenticates with.
    func pairedPhones() -> [String: Data] {
        var result: [String: Data] = [:]
        for account in keychain.allAccounts() where account.hasPrefix(Self.pairedPrefix) {
            let phoneID = String(account.dropFirst(Self.pairedPrefix.count))
            if let secret = keychain.data(forAccount: account) {
                result[phoneID] = secret
            }
        }
        return result
    }

    /// Mints and stores a fresh session secret for a phone that just paired.
    func pair(phoneID: String) -> Data {
        let secret = Self.randomSecret()
        keychain.set(secret, forAccount: Self.pairedPrefix + phoneID)
        return secret
    }

    /// FR-5: unpairing from the Mac's menu drops the phone's key, so it needs the PIN
    /// again.
    @discardableResult
    func unpair(phoneID: String) -> Bool {
        keychain.removeItem(forAccount: Self.pairedPrefix + phoneID)
    }

    func isPaired(phoneID: String) -> Bool {
        keychain.data(forAccount: Self.pairedPrefix + phoneID) != nil
    }

    private static func randomSecret() -> Data {
        // CryptoKit's key generation, rather than anything built on Int.random: this is
        // the value that stands in for a password for the life of the pairing.
        SymmetricKey(size: SymmetricKeySize(bitCount: DeckService.sessionSecretByteCount * 8))
            .withUnsafeBytes { Data($0) }
    }
}
