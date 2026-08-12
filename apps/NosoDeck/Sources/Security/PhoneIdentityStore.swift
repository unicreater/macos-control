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
        let fresh = UUID().uuidString
        keychain.set(Data(fresh.utf8), forAccount: Self.deviceIDAccount)
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
        guard let data = keychain.data(forAccount: Self.trustAccount),
              let store = try? JSONDecoder().decode(TrustStore.self, from: data) else {
            return TrustStore()
        }
        return store
    }

    func save(_ trust: TrustStore) {
        guard let data = try? JSONEncoder().encode(trust) else { return }
        keychain.set(data, forAccount: Self.trustAccount)
    }

    // MARK: - Session secrets

    func sessionSecret(forMacID macID: String) -> Data? {
        keychain.data(forAccount: Self.secretPrefix + macID)
    }

    func setSessionSecret(_ secret: Data, forMacID macID: String) {
        keychain.set(secret, forAccount: Self.secretPrefix + macID)
    }

    func removeSessionSecret(forMacID macID: String) {
        keychain.removeItem(forAccount: Self.secretPrefix + macID)
    }

    /// Unpair (FR-5): drop both halves at once, so no stale key can outlive the trust
    /// that justified it.
    func forget(macID: String) {
        removeSessionSecret(forMacID: macID)
        var trust = loadTrust()
        trust.forget(deviceID: macID)
        save(trust)
    }
}
