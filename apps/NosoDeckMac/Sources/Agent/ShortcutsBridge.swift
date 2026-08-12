import AppKit
import DeckKit
import Foundation

/// Lists and runs the Mac's Apple Shortcuts (FR-13).
///
/// Driven through Shortcuts Events with Apple Events, which is the sandbox-legal route
/// the PRD's entitlement plan chose: `com.apple.security.automation.apple-events` plus
/// `NSAppleEventsUsageDescription`, with the user consenting once. The `shortcuts` CLI
/// is not reachable from a sandboxed process, and neither is the Shortcuts database.
///
/// `NSAppleScript` is not thread-safe, so everything here stays on the main actor.
@MainActor
struct ShortcutsBridge {
    private static let targetBundleID = "com.apple.shortcuts.events"

    /// Whether the user has consented to this Mac being automated (FR-24).
    ///
    /// Asking without prompting is what lets the pre-prompt card appear *before* the
    /// system dialog rather than after it.
    func permissionStatus(promptIfNeeded: Bool = false) -> PermissionStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: Self.targetBundleID)
        guard let descriptor = target.aeDesc else { return .notDetermined }

        let status = AEDeterminePermissionToAutomateTarget(
            descriptor,
            typeWildCard,
            typeWildCard,
            promptIfNeeded
        )

        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            // errAEEventWouldRequireUserConsent, and anything else we cannot read as a
            // definite no.
            return .notDetermined
        }
    }

    /// Every shortcut's name, or an empty list when consent is missing — the phone
    /// shows the degraded path rather than an empty tab with no explanation.
    func names() -> [String] {
        let script = """
        tell application "Shortcuts Events" to get name of every shortcut
        """
        guard let descriptor = run(script: script) else { return [] }

        // A list of strings comes back as a descriptor list, one-indexed.
        guard descriptor.numberOfItems > 0 else {
            return descriptor.stringValue.map { [$0] } ?? []
        }
        return (1...descriptor.numberOfItems).compactMap {
            descriptor.atIndex($0)?.stringValue
        }
    }

    func run(named name: String) -> Result<Void, ActionFailure> {
        guard permissionStatus() == .granted else {
            return .failure(.notPermitted(
                "NosoDeck needs permission to control Shortcuts. Allow it in System Settings → Privacy & Security → Automation."
            ))
        }

        // Quoted rather than interpolated raw: a shortcut named with a quote would
        // otherwise end the string and change what the script does.
        let script = """
        tell application "Shortcuts Events" to run shortcut named \(appleScriptString(name))
        """
        guard run(script: script) != nil else {
            return .failure(.systemError("Couldn't run “\(name)”. It may have been renamed or deleted."))
        }
        return .success(())
    }

    private func run(script source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    /// Escapes a Swift string into an AppleScript string literal.
    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
