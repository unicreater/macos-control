import AppKit
import DeckKit
import SwiftUI

/// The agent's entire UI (FR-19): connection state, the paired device, the PIN while
/// unpaired, and Quit.
///
/// Built with plain macOS menu conventions rather than the phone's Hardware visual
/// language — the handoff leaves the Mac surfaces undesigned, and a native menu is the
/// honest placeholder until that design round happens.
struct AgentMenu: View {
    let agent: AgentModel

    var body: some View {
        Text(agent.status.menuDescription)

        Divider()

        if agent.pairedPhones.isEmpty {
            Text("Pairing PIN:  \(spacedPIN)")
            Button("New PIN") {
                agent.rotatePIN()
            }
            Text("Enter it on your iPhone to pair.")
        } else {
            ForEach(agent.pairedPhones) { phone in
                Button("Forget \(phone.name)") {
                    agent.unpair(phoneID: phone.deviceID)
                }
            }
            Button("Pair another iPhone…  (PIN \(spacedPIN))") {
                agent.rotatePIN()
            }
        }

        Divider()

        Button("Quit NosoDeck") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Grouped three and three, which is how people read a six-digit code aloud.
    private var spacedPIN: String {
        let digits = agent.pin.digits
        let midpoint = digits.index(digits.startIndex, offsetBy: 3)
        return "\(digits[..<midpoint]) \(digits[midpoint...])"
    }
}
