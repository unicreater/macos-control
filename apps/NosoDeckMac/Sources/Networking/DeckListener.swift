import DeckKit
import Foundation
import Network

/// Advertises `_nosodeck._tcp` and accepts TLS connections from paired phones (FR-1).
///
/// The set of acceptable keys is baked into the listener's parameters, so it has to be
/// rebuilt whenever that set changes — a phone pairs, a phone is unpaired, or the PIN
/// rotates. `restart(...)` is the only entry point for that reason.
@MainActor
final class DeckListener {
    private var listener: NWListener?

    var onConnection: ((PeerConnection) -> Void)?
    var onStateChange: ((NWListener.State) -> Void)?

    private(set) var isRunning = false

    /// Starts, or restarts with a new key set.
    func restart(serviceName: String, deviceID: String, keys: [PresharedKey]) throws {
        stop()

        let listener = try NWListener(using: DeckTransport.parameters(keys: keys))

        var txtRecord = NWTXTRecord()
        txtRecord[DeckService.txtDeviceIDKey] = deviceID
        txtRecord[DeckService.txtNameKey] = serviceName
        txtRecord[DeckService.txtProtocolVersionKey] = String(DeckKitVersion.wireProtocol)

        listener.service = NWListener.Service(
            name: serviceName,
            type: DeckService.bonjourType,
            domain: nil,
            txtRecord: txtRecord
        )

        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    self.isRunning = true
                case .failed, .cancelled:
                    self.isRunning = false
                default:
                    break
                }
                self.onStateChange?(state)
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                guard let self else {
                    connection.cancel()
                    return
                }
                self.onConnection?(PeerConnection(connection: connection))
            }
        }

        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        isRunning = false
    }
}
