import AppKit
import DeckKit
import Foundation

/// Carries out what a tile tap asks for.
///
/// Every failure carries a message the phone can show, because a tile that does nothing
/// and says nothing is the worst outcome available.
@MainActor
struct ActionExecutor {
    private let shortcuts = ShortcutsBridge()
    private let inserter = TextInserter()

    func perform(_ request: ActionRequest) async -> Result<Void, ActionFailure> {
        switch request.kind {
        case .activateApp:
            return await activate(bundleID: request.target)
        case .quitApp:
            return quit(bundleID: request.target)
        case .runShortcut:
            return shortcuts.run(named: request.target)
        case .openURL:
            return openURL(request.target)
        case .insertText:
            return inserter.insert(request.target)
        case .maximizeWindow:
            return sendKeyCombo(key: 0x03, modifiers: [.maskControl, .maskCommand]) // Ctrl+Cmd+F (fullscreen toggle)
        case .minimizeWindow:
            return sendKeyCombo(key: 0x2E, modifiers: .maskCommand) // Cmd+M
        case .copyClipboard:
            return sendKeyCombo(key: 0x08, modifiers: .maskCommand) // Cmd+C
        case .pasteClipboard:
            return sendKeyCombo(key: 0x09, modifiers: .maskCommand) // Cmd+V
        }
    }

    /// Smart URL opening: if the URL is already open in a browser tab, switch to it.
    /// Otherwise open it normally (FR-14).
    private func openURL(_ raw: String) -> Result<Void, ActionFailure> {
        guard TileTarget.isValidWebsiteURL(raw), let url = URL(string: raw.trimmingCharacters(in: .whitespaces)) else {
            return .failure(.notFound("\(raw) isn't a valid web address"))
        }

        // Try to switch to an existing tab first
        if switchToTab(url: raw) {
            return .success(())
        }

        guard NSWorkspace.shared.open(url) else {
            return .failure(.systemError("Nothing on this Mac could open that address"))
        }
        return .success(())
    }

    /// Checks running browsers for a tab matching the URL and switches to it.
    private func switchToTab(url: String) -> Bool {
        // Try Chrome-based browsers first (most common)
        let chromiumBrowsers = [
            ("Google Chrome", "com.google.Chrome"),
            ("Arc", "company.thebrowser.Browser"),
            ("Microsoft Edge", "com.microsoft.edgemac"),
            ("Brave Browser", "com.brave.Browser"),
        ]
        for (name, bundleID) in chromiumBrowsers {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first != nil {
                if switchChromiumTab(app: name, url: url) { return true }
            }
        }
        // Try Safari
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first != nil {
            if switchSafariTab(url: url) { return true }
        }
        return false
    }

    private func switchChromiumTab(app: String, url: String) -> Bool {
        let script = """
        tell application "\(app)"
            repeat with w in windows
                set tabIndex to 0
                repeat with t in tabs of w
                    set tabIndex to tabIndex + 1
                    if URL of t contains "\(url.replacingOccurrences(of: "\"", with: "\\\""))" then
                        set active tab index of w to tabIndex
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
            return false
        end tell
        """
        let result = runAppleScript(script)
        return result == "true"
    }

    private func switchSafariTab(url: String) -> Bool {
        let script = """
        tell application "Safari"
            repeat with w in windows
                set tabIndex to 0
                repeat with t in tabs of w
                    set tabIndex to tabIndex + 1
                    if URL of t contains "\(url.replacingOccurrences(of: "\"", with: "\\\""))" then
                        set current tab of w to t
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
            return false
        end tell
        """
        let result = runAppleScript(script)
        return result == "true"
    }

    private func runAppleScript(_ source: String) -> String {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return result?.stringValue ?? ""
    }

    /// Launch if closed, bring to front if running — `openApplication` does both, which
    /// is why it is used in place of `NSRunningApplication.activate` and avoids that
    /// API's macOS 14 deprecation entirely.
    private func activate(bundleID target: String) async -> Result<Void, ActionFailure> {
        // Parse "bundleID:windowID" format for specific window activation
        let parts = target.split(separator: ":", maxSplits: 1)
        let bundleID = String(parts[0])
        let windowID = parts.count > 1 ? Int(parts[1]) : nil

        // If a specific window is requested, raise it via Accessibility
        if let windowID {
            if raiseWindow(bundleID: bundleID, windowNumber: windowID) {
                return .success(())
            }
        }

        // Fallback: bring all windows to front
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if let app = running.first {
            app.activate(options: .activateAllWindows)
            return .success(())
        }

        // Not running — launch it.
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return .failure(.notFound("\(bundleID) isn't installed on this Mac"))
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return .success(())
        } catch {
            return .failure(.systemError(error.localizedDescription))
        }
    }

    /// Raises a specific window by CGWindowNumber. Handles cross-Space switching.
    private func raiseWindow(bundleID: String, windowNumber: Int) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }

        // CGWindowList sees ALL windows including other Spaces
        let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let targetInfo = windowList.first { ($0["kCGWindowNumber"] as? Int) == windowNumber }
        let targetTitle = targetInfo?["kCGWindowName"] as? String ?? ""

        // Extract project name from "project-name . context . uuid" format
        let projectName = targetTitle.components(separatedBy: " \u{00b7} ").first ?? targetTitle
        let appName = app.localizedName ?? bundleID.components(separatedBy: ".").last ?? "App"

        // First activate the app — this may switch Spaces to where Warp is most recently used
        app.activate(options: .activateAllWindows)

        // Then use AppleScript to raise the specific window by project name
        if !projectName.isEmpty {
            let safeName = projectName.replacingOccurrences(of: "\"", with: "")
            let script = """
            delay 0.3
            tell application "System Events"
                tell process "\(appName)"
                    set allWindows to every window
                    repeat with w in allWindows
                        if name of w contains "\(safeName)" then
                            perform action "AXRaise" of w
                            return "raised"
                        end if
                    end repeat
                end tell
            end tell
            """
            let s = NSAppleScript(source: script)
            var err: NSDictionary?
            s?.executeAndReturnError(&err)
        }
        return true
    }

    /// Sends a keyboard shortcut via CGEvent.
    private func sendKeyCombo(key: CGKeyCode, modifiers: CGEventFlags) -> Result<Void, ActionFailure> {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            return .failure(.systemError("Could not create key event"))
        }
        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return .success(())
    }

    /// A graceful terminate, never a force kill (FR-11).
    ///
    /// `terminate()` returning true means the request was delivered, not that the app
    /// is gone — an app with unsaved changes will put up its own save dialog and keep
    /// running. That is correct behaviour, and the tile will still show it running,
    /// which is exactly what FR-11's acceptance criterion describes.
    private func quit(bundleID: String) -> Result<Void, ActionFailure> {
        let matches = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !matches.isEmpty else {
            return .failure(.notFound("\(bundleID) isn't running"))
        }
        for app in matches {
            _ = app.terminate()
        }
        return .success(())
    }
}

enum ActionFailure: Error {
    case notFound(String)
    case notImplemented(String)
    case notPermitted(String)
    case systemError(String)

    /// What travels back in `actionResult.error` and, eventually, in front of the user.
    var message: String {
        switch self {
        case .notFound(let message),
             .notImplemented(let message),
             .notPermitted(let message),
             .systemError(let message):
            return message
        }
    }
}
