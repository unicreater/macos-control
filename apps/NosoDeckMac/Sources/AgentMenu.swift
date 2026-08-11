import AppKit
import DeckKit
import SwiftUI

/// M0 placeholder menu. M2 replaces the version row with the real FR-19 contents:
/// connection state, paired device name, and the 6-digit PIN while unpaired.
struct AgentMenu: View {
    var body: some View {
        Text("DeckKit \(DeckKitVersion.package)")
        Divider()
        Button("Quit NosoDeck") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
