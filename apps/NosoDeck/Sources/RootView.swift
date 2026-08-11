import DeckKit
import SwiftUI

/// M0 placeholder shell. It exists to prove the target builds, links DeckKit, and
/// launches landscape-locked. The design-token theme layer and the real screens land
/// in M3 (onboarding, discovery, PIN, deck shell) and M4 (keycap grid).
struct RootView: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            Text("NOSODECK · DECKKIT \(DeckKitVersion.package)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    RootView()
}
