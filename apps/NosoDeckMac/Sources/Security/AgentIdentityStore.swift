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
    private static let udDeviceIDKey = "com.noso.nosodeck.mac.deviceID"

    private let keychain: KeychainStore
    private let _cachedDeviceID: String
    private let _cachedSecret: Data

    init(keychain: KeychainStore = KeychainStore(service: "com.noso.nosodeck.mac")) {
        self.keychain = keychain

        // Resolve deviceID once at init. Keychain silently fails when unsigned
        // (CODE_SIGNING_ALLOWED=NO), so fall back to UserDefaults.
        if let data = keychain.data(forAccount: Self.deviceIDAccount),
           let existing = String(data: data, encoding: .utf8), !existing.isEmpty {
            _cachedDeviceID = existing
        } else if let ud = UserDefaults.standard.string(forKey: Self.udDeviceIDKey), !ud.isEmpty {
            _cachedDeviceID = ud
            keychain.set(Data(ud.utf8), forAccount: Self.deviceIDAccount)
        } else {
            let fresh = UUID().uuidString
            keychain.set(Data(fresh.utf8), forAccount: Self.deviceIDAccount)
            UserDefaults.standard.set(fresh, forKey: Self.udDeviceIDKey)
            _cachedDeviceID = fresh
        }

        // Same for the long-term secret.
        if let existing = keychain.data(forAccount: Self.secretAccount),
           existing.count == DeckService.sessionSecretByteCount {
            _cachedSecret = existing
        } else if let udHex = UserDefaults.standard.string(forKey: Self.udSecretKey),
                  let udData = Data(hexString: udHex), udData.count == DeckService.sessionSecretByteCount {
            _cachedSecret = udData
            keychain.set(udData, forAccount: Self.secretAccount)
        } else {
            let fresh = Self.randomSecret()
            keychain.set(fresh, forAccount: Self.secretAccount)
            UserDefaults.standard.set(fresh.map { String(format: "%02x", $0) }.joined(), forKey: Self.udSecretKey)
            _cachedSecret = fresh
        }

    }

    // MARK: - This Mac

    var deviceID: String { _cachedDeviceID }

    var secret: Data { _cachedSecret }

    private static let udSecretKey = "com.noso.nosodeck.mac.secret"

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

    private static let udPairedPhonesKey = "com.noso.nosodeck.mac.pairedPhones"

    /// Phone device ID → the session secret that phone authenticates with.
    func pairedPhones() -> [String: Data] {
        var result: [String: Data] = [:]
        // Try keychain first
        for account in keychain.allAccounts() where account.hasPrefix(Self.pairedPrefix) {
            let phoneID = String(account.dropFirst(Self.pairedPrefix.count))
            if let secret = keychain.data(forAccount: account) {
                result[phoneID] = secret
            }
        }
        // Fallback to UserDefaults
        if result.isEmpty, let ud = UserDefaults.standard.dictionary(forKey: Self.udPairedPhonesKey) as? [String: String] {
            for (phoneID, hex) in ud {
                if let data = Data(hexString: hex) {
                    result[phoneID] = data
                }
            }
        }
        return result
    }

    /// Mints and stores a fresh session secret for a phone that just paired.
    func pair(phoneID: String) -> Data {
        let secret = Self.randomSecret()
        keychain.set(secret, forAccount: Self.pairedPrefix + phoneID)
        // UserDefaults fallback
        var ud = (UserDefaults.standard.dictionary(forKey: Self.udPairedPhonesKey) as? [String: String]) ?? [:]
        ud[phoneID] = secret.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(ud, forKey: Self.udPairedPhonesKey)
        return secret
    }

    @discardableResult
    func unpair(phoneID: String) -> Bool {
        var ud = (UserDefaults.standard.dictionary(forKey: Self.udPairedPhonesKey) as? [String: String]) ?? [:]
        ud.removeValue(forKey: phoneID)
        UserDefaults.standard.set(ud, forKey: Self.udPairedPhonesKey)
        return keychain.removeItem(forAccount: Self.pairedPrefix + phoneID)
    }

    func isPaired(phoneID: String) -> Bool {
        if keychain.data(forAccount: Self.pairedPrefix + phoneID) != nil { return true }
        if let ud = UserDefaults.standard.dictionary(forKey: Self.udPairedPhonesKey) as? [String: String] {
            return ud[phoneID] != nil
        }
        return false
    }

    private static func randomSecret() -> Data {
        SymmetricKey(size: SymmetricKeySize(bitCount: DeckService.sessionSecretByteCount * 8))
            .withUnsafeBytes { Data($0) }
    }
}

private extension Data {
    init?(hexString: String) {
        let len = hexString.count
        guard len % 2 == 0 else { return nil }
        var data = Data(capacity: len / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
