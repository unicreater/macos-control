import DeckKit
import Foundation
import Network

/// One TLS link, speaking DeckKit envelopes.
///
/// Both apps use this: the phone opens one, the agent accepts them. It owns the
/// reassembly buffer, so a caller only ever sees whole messages.
///
/// Everything runs on the main queue and the type is `@MainActor`, which keeps the app
/// models free of locks. `MainActor.assumeIsolated` in the callbacks is safe precisely
/// because `start(queue: .main)` guarantees where they land.
@MainActor
final class PeerConnection {
    private let connection: NWConnection
    private var decoder = FrameDecoder()
    private var hasStartedReceiving = false

    var onStateChange: ((NWConnection.State) -> Void)?
    var onEnvelope: ((Envelope) -> Void)?
    var onError: ((Error) -> Void)?

    /// An inbound connection handed over by the listener.
    init(connection: NWConnection) {
        self.connection = connection
    }

    /// An outbound connection to a discovered agent.
    convenience init(endpoint: NWEndpoint, parameters: NWParameters) {
        self.init(connection: NWConnection(to: endpoint, using: parameters))
    }

    var state: NWConnection.State { connection.state }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                if case .ready = state, !self.hasStartedReceiving {
                    self.hasStartedReceiving = true
                    self.receiveNext()
                }
                self.onStateChange?(state)
            }
        }
        connection.start(queue: .main)
    }

    func send(_ envelope: Envelope) {
        do {
            let frame = try FrameCodec.encode(envelope)
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                guard let error else { return }
                MainActor.assumeIsolated { self?.onError?(error) }
            })
        } catch {
            onError?(error)
        }
    }

    func cancel() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }

                if let data, !data.isEmpty {
                    self.decoder.append(data)
                    do {
                        // Frames that fail to decode are reported and skipped; only a
                        // framing error throws, and past one of those the stream can no
                        // longer be trusted.
                        let drained = try self.decoder.drain()
                        for envelope in drained.envelopes {
                            self.onEnvelope?(envelope)
                        }
                        for protocolError in drained.errors {
                            self.onError?(protocolError)
                        }
                    } catch {
                        self.onError?(error)
                        self.cancel()
                        return
                    }
                }

                if let error {
                    self.onError?(error)
                    return
                }
                if isComplete {
                    self.cancel()
                    return
                }
                self.receiveNext()
            }
        }
    }
}
