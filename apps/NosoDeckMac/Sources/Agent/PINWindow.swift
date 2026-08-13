import AppKit
import DeckKit
import Foundation

/// Shows the pairing PIN or connection status in a prominent floating window.
@MainActor
final class PINWindow {
    private var window: NSWindow?

    func show(pin: PairingPIN, macName: String, paired: Bool = false, onUnpair: (() -> Void)? = nil) {
        close()

        let digits = pin.digits
        let mid = digits.index(digits.startIndex, offsetBy: 3)
        let spaced = "\(digits[..<mid])  \(digits[mid...])"

        guard let screen = NSScreen.main else { return }
        let width: CGFloat = 360
        let height: CGFloat = paired ? 240 : 200
        let x = screen.frame.midX - width / 2
        let y = screen.frame.midY - height / 2 + 100

        let win = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "NosoDeck"
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.titlebarAppearsTransparent = true
        win.backgroundColor = NSColor(white: 0.12, alpha: 1)
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        if paired {
            // Connected state
            let statusDot = NSView(frame: NSRect(x: width/2 - 40, y: 160, width: 10, height: 10))
            statusDot.wantsLayer = true
            statusDot.layer?.backgroundColor = NSColor(red: 0.64, green: 0.83, blue: 0.77, alpha: 1).cgColor
            statusDot.layer?.cornerRadius = 5
            container.addSubview(statusDot)

            let statusLabel = NSTextField(labelWithString: "Paired")
            statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
            statusLabel.textColor = NSColor(red: 0.64, green: 0.83, blue: 0.77, alpha: 1)
            statusLabel.frame = NSRect(x: width/2 - 20, y: 155, width: 80, height: 20)
            container.addSubview(statusLabel)

            let pinTitle = NSTextField(labelWithString: "PIN FOR NEW DEVICE")
            pinTitle.font = .systemFont(ofSize: 11, weight: .semibold)
            pinTitle.textColor = NSColor(white: 0.5, alpha: 1)
            pinTitle.alignment = .center
            pinTitle.frame = NSRect(x: 0, y: 118, width: width, height: 16)
            container.addSubview(pinTitle)

            let pinLabel = NSTextField(labelWithString: spaced)
            pinLabel.font = .monospacedSystemFont(ofSize: 44, weight: .bold)
            pinLabel.textColor = .white
            pinLabel.alignment = .center
            pinLabel.frame = NSRect(x: 0, y: 65, width: width, height: 50)
            container.addSubview(pinLabel)

            let unpairButton = NSButton(title: "Unpair All", target: nil, action: nil)
            unpairButton.bezelStyle = .rounded
            unpairButton.frame = NSRect(x: width/2 - 50, y: 20, width: 100, height: 30)
            unpairButton.target = UnpairTarget.shared
            UnpairTarget.shared.action = {
                onUnpair?()
            }
            unpairButton.action = #selector(UnpairTarget.handleUnpair)
            container.addSubview(unpairButton)
        } else {
            let titleLabel = NSTextField(labelWithString: "PAIRING PIN")
            titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            titleLabel.textColor = NSColor(white: 0.5, alpha: 1)
            titleLabel.alignment = .center
            titleLabel.frame = NSRect(x: 0, y: 138, width: width, height: 16)
            container.addSubview(titleLabel)

            let pinLabel = NSTextField(labelWithString: spaced)
            pinLabel.font = .monospacedSystemFont(ofSize: 52, weight: .bold)
            pinLabel.textColor = .white
            pinLabel.alignment = .center
            pinLabel.frame = NSRect(x: 0, y: 75, width: width, height: 56)
            container.addSubview(pinLabel)

            let infoLabel = NSTextField(labelWithString: "Enter this on your iPhone to connect to\n\(macName)")
            infoLabel.font = .systemFont(ofSize: 12)
            infoLabel.textColor = NSColor(white: 0.45, alpha: 1)
            infoLabel.alignment = .center
            infoLabel.maximumNumberOfLines = 2
            infoLabel.frame = NSRect(x: 20, y: 25, width: width - 40, height: 36)
            container.addSubview(infoLabel)
        }

        win.contentView = container

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)

        self.window = win
    }

    func close() {
        window?.close()
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }

    var isVisible: Bool { window?.isVisible ?? false }
}

/// Helper to bridge NSButton target-action to a closure.
private class UnpairTarget: NSObject {
    static let shared = UnpairTarget()
    var action: (() -> Void)?

    @objc func handleUnpair() {
        action?()
    }
}
