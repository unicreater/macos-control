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
        // MARK: - Radial menu actions
        case .mediaPlayPause:
            return sendMediaKey(NX_KEYTYPE_PLAY)
        case .mediaNextTrack:
            return sendMediaKey(NX_KEYTYPE_NEXT)
        case .mediaPreviousTrack:
            return sendMediaKey(NX_KEYTYPE_PREVIOUS)
        case .seekForward:
            return sendKeyCombo(key: 0x7C, modifiers: []) // Right arrow
        case .seekBackward:
            return sendKeyCombo(key: 0x7B, modifiers: []) // Left arrow
        case .volumeUp:
            return sendMediaKey(NX_KEYTYPE_SOUND_UP)
        case .volumeDown:
            return sendMediaKey(NX_KEYTYPE_SOUND_DOWN)
        case .volumeMute:
            return sendMediaKey(NX_KEYTYPE_MUTE)
        case .goBack:
            return sendKeyCombo(key: 0x21, modifiers: .maskCommand) // Cmd+[
        case .goForward:
            return sendKeyCombo(key: 0x1E, modifiers: .maskCommand) // Cmd+]
        case .refreshPage:
            return sendKeyCombo(key: 0x0F, modifiers: .maskCommand) // Cmd+R
        case .closeTab:
            return sendKeyCombo(key: 0x0D, modifiers: .maskCommand) // Cmd+W
        case .newTab:
            return sendKeyCombo(key: 0x11, modifiers: .maskCommand) // Cmd+T
        case .scrollUp:
            return sendScroll(deltaY: 5)
        case .scrollDown:
            return sendScroll(deltaY: -5)
        case .keyCombo:
            return performKeyCombo(request.target)
        case .moveMouse:
            return moveMouseBy(request.target)
        case .mouseClick:
            return mouseClick()
        case .mouseDown:
            return mouseButton(down: true)
        case .mouseUp:
            return mouseButton(down: false)
        case .scrollMouse:
            return scrollBy(request.target)
        case .pinchZoom:
            return zoomBy(request.target)
        }
    }

    /// Parses a combo string like "cmd+shift+3" and sends the corresponding CGEvent.
    private func performKeyCombo(_ combo: String) -> Result<Void, ActionFailure> {
        let parts = combo.lowercased().components(separatedBy: "+")
        guard let keyPart = parts.last, !keyPart.isEmpty else {
            return .failure(.systemError("Empty key combo"))
        }
        let modParts = parts.dropLast()

        var flags: CGEventFlags = []
        for mod in modParts {
            switch mod {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "alt", "option", "opt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: break
            }
        }

        guard let keyCode = Self.keyCodeMap[keyPart] else {
            return .failure(.systemError("Unknown key: \(keyPart)"))
        }

        return sendKeyCombo(key: keyCode, modifiers: flags)
    }

    private static let keyCodeMap: [String: CGKeyCode] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "o": 0x1F,
        "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28,
        "n": 0x2D, "m": 0x2E,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17, "6": 0x16,
        "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,
        "space": 0x31, "return": 0x24, "enter": 0x24, "tab": 0x30,
        "escape": 0x35, "esc": 0x35, "delete": 0x33, "backspace": 0x33,
        "up": 0x7E, "down": 0x7D, "left": 0x7B, "right": 0x7C,
        "[": 0x21, "]": 0x1E, "-": 0x1B, "=": 0x18,
        ";": 0x29, "'": 0x27, ",": 0x2B, ".": 0x2F, "/": 0x2C, "\\": 0x2A,
        "`": 0x32,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60,
        "f6": 0x61, "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D,
        "f11": 0x67, "f12": 0x6F,
    ]

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

    /// Sends a media key event (play/pause, next, previous, volume).
    private func sendMediaKey(_ keyType: Int32) -> Result<Void, ActionFailure> {
        func doKeyPress(down: Bool) {
            let flags: UInt32 = down ? 0x0A00 : 0x0B00 // NX key down / up
            let data = (UInt32(keyType) << 16) | flags
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8, // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                data1: Int(data),
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        doKeyPress(down: true)
        doKeyPress(down: false)
        return .success(())
    }

    /// Sends a scroll wheel event.
    private func sendScroll(deltaY: Int32) -> Result<Void, ActionFailure> {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: deltaY, wheel2: 0, wheel3: 0) else {
            return .failure(.systemError("Could not create scroll event"))
        }
        event.post(tap: .cghidEventTap)
        return .success(())
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

    // MARK: - Touchpad

    private func moveMouseBy(_ target: String) -> Result<Void, ActionFailure> {
        let parts = target.split(separator: ",")
        guard parts.count == 2,
              let dx = Double(parts[0]), let dy = Double(parts[1]) else {
            return .failure(.systemError("Invalid move format"))
        }
        let current = CGEvent(source: nil)?.location ?? .zero
        let dest = CGPoint(x: current.x + dx, y: current.y + dy)
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: dest, mouseButton: .left) else {
            return .failure(.systemError("Could not create mouse event"))
        }
        event.post(tap: .cghidEventTap)
        return .success(())
    }

    private func mouseClick() -> Result<Void, ActionFailure> {
        let pos = CGEvent(source: nil)?.location ?? .zero
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pos, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left) else {
            return .failure(.systemError("Could not create click event"))
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return .success(())
    }

    private func mouseButton(down: Bool) -> Result<Void, ActionFailure> {
        let pos = CGEvent(source: nil)?.location ?? .zero
        let type: CGEventType = down ? .leftMouseDown : .leftMouseUp
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: pos, mouseButton: .left) else {
            return .failure(.systemError("Could not create mouse event"))
        }
        event.post(tap: .cghidEventTap)
        return .success(())
    }

    private func scrollBy(_ target: String) -> Result<Void, ActionFailure> {
        guard let dy = Double(target) else {
            return .failure(.systemError("Invalid scroll value"))
        }
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(dy), wheel2: 0, wheel3: 0) else {
            return .failure(.systemError("Could not create scroll event"))
        }
        event.post(tap: .cghidEventTap)
        return .success(())
    }

    private func zoomBy(_ target: String) -> Result<Void, ActionFailure> {
        guard let scale = Double(target) else {
            return .failure(.systemError("Invalid zoom value"))
        }
        // Zoom = Cmd + scroll
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(scale * 10), wheel2: 0, wheel3: 0) else {
            return .failure(.systemError("Could not create zoom event"))
        }
        event.flags = .maskCommand
        event.post(tap: .cghidEventTap)
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
