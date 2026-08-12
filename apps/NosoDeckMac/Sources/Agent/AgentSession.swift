import DeckKit
import Foundation

/// One connected phone, for as long as its link lasts.
@MainActor
final class AgentSession: Identifiable {
    nonisolated let id = UUID()
    let connection: PeerConnection

    /// Set once the phone's `hello` arrives. Until then nothing about the peer is known
    /// beyond the fact that it satisfied the TLS handshake.
    private(set) var hello: Hello?
    /// Whether this phone was already trusted when it connected.
    private(set) var isPaired = false

    init(connection: PeerConnection) {
        self.connection = connection
    }

    var phoneID: String? { hello?.deviceID }
    var phoneName: String? { hello?.deviceName }

    func adopt(hello: Hello, isPaired: Bool) {
        self.hello = hello
        self.isPaired = isPaired
    }

    func markPaired() {
        isPaired = true
    }
}
