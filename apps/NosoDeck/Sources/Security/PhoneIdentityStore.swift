import DeckKit
import Foundation
import UIKit

/// This phone's identity and everything it knows about the Macs it trusts.
///
/// DeckKit owns *what counts* as trusted (`TrustStore`); this owns where that lives.
/// Both the pinned fingerprints and the per-Mac session secrets go in the Keychain, so
/// they survive relaunch — which is what makes FR-2's "no PIN prompt after a relaunch"
/// true — and are gone after a delete-and-reinstall, which is correct.
struct PhoneIdentityStore {
    private static let deviceIDAccount = "phone.deviceID"
    private static let trustAccount = "phone.trust"
    private static let secretPrefix = "mac."
    private static let udDeviceIDKey = "com.noso.nosodeck.ios.deviceID"
    private static let udTrustKey = "com.noso.nosodeck.ios.trust"
    private static let udSecretPrefix = "com.noso.nosodeck.ios.secret."

    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore(service: "com.noso.nosodeck.ios")) {
        self.keychain = keychain
    }

    /// Stable ID for this install, minted once.
    var deviceID: String {
        if let data = keychain.data(forAccount: Self.deviceIDAccount),
           let existing = String(data: data, encoding: .utf8), !existing.isEmpty {
            return existing
        }
        // UserDefaults fallback for unsigned builds
        if let ud = UserDefaults.standard.string(forKey: Self.udDeviceIDKey), !ud.isEmpty {
            keychain.set(Data(ud.utf8), forAccount: Self.deviceIDAccount)
            return ud
        }
        let fresh = UUID().uuidString
        keychain.set(Data(fresh.utf8), forAccount: Self.deviceIDAccount)
        UserDefaults.standard.set(fresh, forKey: Self.udDeviceIDKey)
        return fresh
    }

    /// What the Mac's menu shows as the paired device.
    var deviceName: String {
        UIDevice.current.name
    }

    /// The phone's half of the handshake.
    func hello() -> Hello {
        Hello(deviceName: deviceName, deviceID: deviceID)
    }

    // MARK: - Pinned identities

    func loadTrust() -> TrustStore {
        // Try keychain first
        if let data = keychain.data(forAccount: Self.trustAccount),
           let store = try? JSONDecoder().decode(TrustStore.self, from: data) {
            return store
        }
        // UserDefaults fallback
        if let data = UserDefaults.standard.data(forKey: Self.udTrustKey),
           let store = try? JSONDecoder().decode(TrustStore.self, from: data) {
            keychain.set(data, forAccount: Self.trustAccount)
            return store
        }
        return TrustStore()
    }

    func save(_ trust: TrustStore) {
        guard let data = try? JSONEncoder().encode(trust) else { return }
        keychain.set(data, forAccount: Self.trustAccount)
        UserDefaults.standard.set(data, forKey: Self.udTrustKey)
    }

    // MARK: - Session secrets

    func sessionSecret(forMacID macID: String) -> Data? {
        if let data = keychain.data(forAccount: Self.secretPrefix + macID) {
            return data
        }
        // UserDefaults fallback
        if let hex = UserDefaults.standard.string(forKey: Self.udSecretPrefix + macID),
           let data = Data(hexString: hex) {
            keychain.set(data, forAccount: Self.secretPrefix + macID)
            return data
        }
        return nil
    }

    func setSessionSecret(_ secret: Data, forMacID macID: String) {
        keychain.set(secret, forAccount: Self.secretPrefix + macID)
        UserDefaults.standard.set(secret.map { String(format: "%02x", $0) }.joined(),
                                  forKey: Self.udSecretPrefix + macID)
    }

    func removeSessionSecret(forMacID macID: String) {
        keychain.removeItem(forAccount: Self.secretPrefix + macID)
        UserDefaults.standard.removeObject(forKey: Self.udSecretPrefix + macID)
    }

    func forget(macID: String) {
        removeSessionSecret(forMacID: macID)
        var trust = loadTrust()
        trust.forget(deviceID: macID)
        save(trust)
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
