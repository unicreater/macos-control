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

    /// Every shortcut's name, or an empty list when consent is missing.
    func names() -> [String] {
        shortcutInfos().map(\.name)
    }

    /// Shortcut names with their colors.
    func shortcutInfos() -> [ShortcutInfo] {
        let script = """
        tell application "Shortcuts Events"
            set output to ""
            repeat with s in every shortcut
                set c to color of s
                set output to output & name of s & "\\t" & item 1 of c & "," & item 2 of c & "," & item 3 of c & "\\n"
            end repeat
            return output
        end tell
        """
        guard let descriptor = run(script: script), let raw = descriptor.stringValue else { return [] }

        return raw.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line in
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 2 else { return nil }
                let name = parts[0]
                let rgb = parts[1].components(separatedBy: ",")
                guard rgb.count == 3,
                      let r = UInt32(rgb[0].trimmingCharacters(in: .whitespaces)),
                      let g = UInt32(rgb[1].trimmingCharacters(in: .whitespaces)),
                      let b = UInt32(rgb[2].trimmingCharacters(in: .whitespaces)) else {
                    return ShortcutInfo(name: name)
                }
                // Shortcuts uses 16-bit color (0-65535), convert to 8-bit
                return ShortcutInfo(name: name, colorR: UInt8(r >> 8), colorG: UInt8(g >> 8), colorB: UInt8(b >> 8))
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
