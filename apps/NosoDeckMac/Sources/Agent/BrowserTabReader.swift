import AppKit
import DeckKit
import Foundation

/// Reads open tabs from the user's browsers via AppleScript.
/// Supports Safari, Chrome, Arc, Edge, Brave, and Firefox.
struct BrowserTabReader {

    func tabs() -> [BrowserTab] {
        var result: [BrowserTab] = []
        result.append(contentsOf: chromiumTabs(app: "Google Chrome"))
        result.append(contentsOf: arcTabs())
        result.append(contentsOf: chromiumTabs(app: "Microsoft Edge"))
        result.append(contentsOf: chromiumTabs(app: "Brave Browser"))
        result.append(contentsOf: safariTabs())
        return result
    }

    private static let browserBundleIDs: [String: String] = [
        "Google Chrome": "com.google.Chrome",
        "Arc": "company.thebrowser.Browser",
        "Microsoft Edge": "com.microsoft.edgemac",
        "Brave Browser": "com.brave.Browser",
        "Safari": "com.apple.Safari",
    ]

    private func safariTabs() -> [BrowserTab] {
        let bundleID = Self.browserBundleIDs["Safari"]!
        guard isRunning(bundleID) else { return [] }
        let script = """
        tell application "Safari"
            set tabList to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set tabList to tabList & name of t & "\\t" & URL of t & "\\n"
                end repeat
            end repeat
            return tabList
        end tell
        """
        return parseTabs(runAppleScript(script), browser: "Safari", bundleID: bundleID)
    }

    /// Arc: iterate spaces to get folder names. Deduplicates by URL.
    private func arcTabs() -> [BrowserTab] {
        let bundleID = Self.browserBundleIDs["Arc"]!
        guard isRunning(bundleID) else { return [] }
        // Each line: spaceName \t title \t url
        let script = """
        tell application "Arc"
            set tabList to ""
            repeat with w in windows
                try
                    repeat with s in spaces of w
                        set spaceName to title of s
                        repeat with t in tabs of s
                            set tabURL to URL of t
                            if tabURL starts with "http" then
                                set tabList to tabList & spaceName & "\\t" & title of t & "\\t" & tabURL & "\\n"
                            end if
                        end repeat
                    end repeat
                end try
            end repeat
            return tabList
        end tell
        """
        let raw = runAppleScript(script)
        var seen = Set<String>()
        return raw.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line in
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 3, !parts[2].isEmpty else { return nil }
                let url = parts[2]
                guard url.hasPrefix("http://") || url.hasPrefix("https://") else { return nil }
                guard seen.insert(url).inserted else { return nil }
                let folder = parts[0].isEmpty ? nil : parts[0]
                return BrowserTab(title: parts[1], url: url, browser: "Arc", browserBundleID: bundleID, folder: folder)
            }
    }

    private func chromiumTabs(app: String) -> [BrowserTab] {
        guard let bundleID = Self.browserBundleIDs[app], isRunning(bundleID) else { return [] }
        let script = """
        tell application "\(app)"
            set tabList to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set tabList to tabList & title of t & "\\t" & URL of t & "\\n"
                end repeat
            end repeat
            return tabList
        end tell
        """
        return parseTabs(runAppleScript(script), browser: app, bundleID: bundleID)
    }

    private func parseTabs(_ raw: String, browser: String, bundleID: String) -> [BrowserTab] {
        raw.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line in
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 2, !parts[1].isEmpty else { return nil }
                let url = parts[1]
                guard url.hasPrefix("http://") || url.hasPrefix("https://") else { return nil }
                return BrowserTab(title: parts[0], url: url, browser: browser, browserBundleID: bundleID)
            }
    }

    private func runAppleScript(_ source: String) -> String {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return result?.stringValue ?? ""
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}
