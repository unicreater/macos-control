import DeckKit
import Foundation
import Network

/// A Mac seen on the local network (FR-1).
struct DiscoveredMac: Identifiable, Hashable, Sendable {
    var deviceID: String
    var name: String
    var fingerprint: String
    var protocolVersion: Int
    var endpoint: NWEndpoint

    var id: String { deviceID }

    /// The identity the pairing machine evaluates trust against. Everything in it comes
    /// from the TXT record, so trust is decided before a single byte is sent.
    var identity: DeviceIdentity {
        DeviceIdentity(deviceID: deviceID, name: name, publicKeyHash: fingerprint)
    }

    var speaksOurProtocol: Bool { protocolVersion == DeckKitVersion.wireProtocol }
}

/// Browses for `_nosodeck._tcp`.
///
/// Starting this is what triggers iOS's local-network permission prompt, so it must not
/// begin until the pre-prompt card has been shown and accepted (FR-24).
@MainActor
final class DeckBrowser {
    private var browser: NWBrowser?

    var onResults: (([DiscoveredMac]) -> Void)?
    var onStateChange: ((NWBrowser.State) -> Void)?

    private(set) var isBrowsing = false

    func start() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = false

        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: DeckService.bonjourType, domain: nil),
            using: parameters
        )

        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    self.isBrowsing = true
                case .failed, .cancelled:
                    self.isBrowsing = false
                default:
                    break
                }
                self.onStateChange?(state)
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                self?.onResults?(Self.macs(from: results))
            }
        }

        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.stateUpdateHandler = nil
        browser?.browseResultsChangedHandler = nil
        browser?.cancel()
        browser = nil
        isBrowsing = false
    }

    /// Results without a usable TXT record are dropped rather than shown as a nameless
    /// row: something else answering on this service type is not a Mac we can pair with.
    private static func macs(from results: Set<NWBrowser.Result>) -> [DiscoveredMac] {
        results.compactMap { result -> DiscoveredMac? in
            guard case .bonjour(let txtRecord) = result.metadata else { return nil }
            guard let deviceID = txtRecord[DeckService.txtDeviceIDKey], !deviceID.isEmpty else {
                return nil
            }
            return DiscoveredMac(
                deviceID: deviceID,
                name: txtRecord[DeckService.txtNameKey] ?? "Mac",
                fingerprint: txtRecord[DeckService.txtFingerprintKey] ?? "",
                protocolVersion: Int(txtRecord[DeckService.txtProtocolVersionKey] ?? "") ?? 0,
                endpoint: result.endpoint
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
