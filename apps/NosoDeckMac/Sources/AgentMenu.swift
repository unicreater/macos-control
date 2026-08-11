import AppKit
import DeckKit
import Foundation
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

        // FR-15's opt-in: Accessibility is asked for here and nowhere else, and only
        // when the user chooses to turn typing on.
        Toggle("Type emoji from the deck", isOn: emojiInsertionBinding)
        Text(agent.isEmojiInsertionTrusted
             ? "Emoji are typed into whatever you're writing."
             : "Off: emoji are copied to the clipboard instead.")

        // FR-20.
        Toggle("Open at login", isOn: loginItemBinding)
        if agent.loginItemNeedsApproval {
            Text("Waiting for approval in System Settings → General → Login Items.")
        }
        if let error = agent.loginItemError {
            Text(error)
        }

        Divider()

        Button("Quit NosoDeck") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Turning it on raises the Accessibility prompt; turning it off is a note that the
    /// grant is revoked in System Settings, since no app can revoke its own.
    private var emojiInsertionBinding: Binding<Bool> {
        Binding(
            get: { agent.isEmojiInsertionTrusted },
            set: { isOn in if isOn { agent.requestEmojiInsertionTrust() } }
        )
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { agent.opensAtLogin },
            set: { agent.setOpensAtLogin($0) }
        )
    }

    /// Grouped three and three, which is how people read a six-digit code aloud.
    private var spacedPIN: String {
        let digits = agent.pin.digits
        let midpoint = digits.index(digits.startIndex, offsetBy: 3)
        return "\(digits[..<midpoint]) \(digits[midpoint...])"
    }
}
