import AppKit
import ApplicationServices
import DeckKit
import Foundation

/// Types text into whatever is focused on the Mac.
/// Uses clipboard + synthetic Cmd+V when Accessibility is trusted,
/// falls back to clipboard-only with a notification otherwise.
@MainActor
struct TextInserter {
    var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func insert(_ text: String) -> Result<Void, ActionFailure> {
        guard !text.isEmpty else { return .failure(.notFound("Nothing to insert")) }

        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard isTrusted else {
            // No Accessibility — text is on clipboard, user can Cmd+V manually
            requestTrust()
            return .success(())
        }

        // Synthetic Cmd+V
        paste()

        // Restore clipboard after paste lands
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            pasteboard.clearContents()
            if let saved {
                pasteboard.setString(saved, forType: .string)
            }
        }

        return .success(())
    }

    private func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode: CGKeyCode = 9 // V key

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
