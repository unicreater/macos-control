import AppKit
import SwiftUI

@main
struct NosoDeckMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar-only agent, no Dock icon and no main window (FR-19). LSUIElement in
        // the generated Info.plist is what keeps it out of the Dock.
        MenuBarExtra {
            AgentMenu(agent: appDelegate.agent)
        } label: {
            // Filled while a phone is connected, outline while merely advertising, so
            // the state reads without opening the menu.
            Image(systemName: appDelegate.agent.isConnected ? "square.grid.2x2.fill" : "square.grid.2x2")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// `MenuBarExtra` has no lifecycle hook of its own, so the agent is started from the
/// app delegate — which is also where the login-item registration will go in M9 (FR-20).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let agent = AgentModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        agent.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        agent.stop()
    }
}
