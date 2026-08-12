import AppKit
import ApplicationServices
import DeckKit
import Foundation
import UserNotifications

/// Types text into whatever is focused on the Mac (FR-15).
///
/// The flakiest feature in v1, which is why it is opt-in and why the fallback is a
/// first-class path rather than an error: without Accessibility the text goes on the
/// clipboard and the Mac says so, and every other feature carries on working.
///
/// The pasteboard is restored afterwards, so using this doesn't cost the user whatever
/// they had copied.
@MainActor
struct TextInserter {
    /// Whether the synthetic-paste path is available right now.
    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Raises the Accessibility prompt. Called only when the user turns the feature on
    /// in Settings, never at launch (FR-24).
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
            // The degraded path, and it is a real one: the text is on the clipboard and
            // the user is told to paste it. Nothing is restored here — taking the text
            // back off the clipboard would defeat the fallback.
            notifyClipboardFallback(for: text)
            return .success(())
        }

        paste()

        // Give the paste time to land before handing the clipboard back. A second is
        // what FR-15's acceptance criterion allows.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            pasteboard.clearContents()
            if let saved {
                pasteboard.setString(saved, forType: .string)
            }
        }

        return .success(())
    }

    /// ⌘V through the HID event tap. Requires Accessibility trust, which `isTrusted`
    /// has already established.
    private func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // 9 is the virtual key code for "v" on every layout — it is positional, not
        // character-based, so this does not break on Dvorak or AZERTY.
        let keyCode: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func notifyClipboardFallback(for text: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "\(text) copied"
            content.body = "Press ⌘V to paste it. Turn on Accessibility for NosoDeck to have it typed for you."

            center.add(UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            ))
        }
    }
}
