import SwiftUI

@main
struct NosoDeckMacApp: App {
    var body: some Scene {
        // Menu-bar-only agent, no Dock icon and no main window (FR-19). LSUIElement in
        // the generated Info.plist is what keeps it out of the Dock.
        MenuBarExtra("NosoDeck", systemImage: "square.grid.2x2") {
            AgentMenu()
        }
        .menuBarExtraStyle(.menu)
    }
}
