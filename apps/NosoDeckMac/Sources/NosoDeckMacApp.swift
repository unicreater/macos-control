import AppKit
import DeckKit
import SwiftUI

@main
struct NosoDeckMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The status item is managed by AppDelegate directly since MenuBarExtra
        // has proven unreliable on some setups. This Scene exists only because
        // SwiftUI App requires at least one.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let agent = AgentModel()
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        agent.start()

        // Start as background agent — PIN window shows only when a phone
        // attempts to pair (triggered by the hello from an unpaired device).
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        agent.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "NosoDeck")
        }

        statusMenu = NSMenu()
        statusItem.menu = statusMenu

        // Rebuild menu each time it opens to show live state.
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: statusMenu,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildMenu()
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()

        // Status
        statusMenu.addItem(NSMenuItem(title: agent.status.menuDescription, action: nil, keyEquivalent: ""))
        statusMenu.addItem(.separator())

        // PIN
        if agent.pairedPhones.isEmpty {
            let digits = agent.pin.digits
            let mid = digits.index(digits.startIndex, offsetBy: 3)
            let spaced = "\(digits[..<mid]) \(digits[mid...])"
            statusMenu.addItem(NSMenuItem(title: "Pairing PIN:  \(spaced)", action: nil, keyEquivalent: ""))

            let newPIN = NSMenuItem(title: "New PIN", action: #selector(rotatePIN), keyEquivalent: "")
            newPIN.target = self
            statusMenu.addItem(newPIN)

            let showPIN = NSMenuItem(title: "Show PIN Window", action: #selector(showPINWindow), keyEquivalent: "")
            showPIN.target = self
            statusMenu.addItem(showPIN)

            statusMenu.addItem(NSMenuItem(title: "Enter it on your iPhone to pair.", action: nil, keyEquivalent: ""))
        } else {
            for phone in agent.pairedPhones {
                let item = NSMenuItem(title: "Forget \(phone.name)", action: #selector(forgetPhone(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = phone.deviceID
                statusMenu.addItem(item)
            }
            let digits = agent.pin.digits
            let mid = digits.index(digits.startIndex, offsetBy: 3)
            let spaced = "\(digits[..<mid]) \(digits[mid...])"
            let pairMore = NSMenuItem(title: "Pair another iPhone…  (PIN \(spaced))", action: #selector(showPINWindow), keyEquivalent: "")
            pairMore.target = self
            statusMenu.addItem(pairMore)
        }

        statusMenu.addItem(.separator())

        // Quit
        let quit = NSMenuItem(title: "Quit NosoDeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusMenu.addItem(quit)
    }

    @objc private func rotatePIN() {
        agent.rotatePIN()
    }

    @objc private func showPINWindow() {
        agent.showPIN()
    }

    @objc private func forgetPhone(_ sender: NSMenuItem) {
        guard let phoneID = sender.representedObject as? String else { return }
        agent.unpair(phoneID: phoneID)
    }
}
