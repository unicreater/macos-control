import AppKit
import DeckKit
import Foundation

/// Reads open tabs from the user's browsers via AppleScript.
/// Supports Safari, Chrome, Arc, Edge, Brave, and Firefox.
struct BrowserTabReader {

    func tabs() -> [BrowserTab] {
        var result: [BrowserTab] = []
        // Try each browser — only running ones will respond.
        result.append(contentsOf: chromiumTabs(app: "Google Chrome"))
        result.append(contentsOf: chromiumTabs(app: "Arc"))
        result.append(contentsOf: chromiumTabs(app: "Microsoft Edge"))
        result.append(contentsOf: chromiumTabs(app: "Brave Browser"))
        result.append(contentsOf: safariTabs())
        // Deduplicate by URL
        var seen: Set<String> = []
        return result.filter { seen.insert($0.url).inserted }
    }

    private func safariTabs() -> [BrowserTab] {
        guard isRunning("com.apple.Safari") else { return [] }
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
        return parseTabs(runAppleScript(script))
    }

    private func chromiumTabs(app: String) -> [BrowserTab] {
        let bundleIDs: [String: String] = [
            "Google Chrome": "com.google.Chrome",
            "Arc": "company.thebrowser.Browser",
            "Microsoft Edge": "com.microsoft.edgemac",
            "Brave Browser": "com.brave.Browser",
        ]
        guard let bundleID = bundleIDs[app], isRunning(bundleID) else { return [] }
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
        return parseTabs(runAppleScript(script))
    }

    private func parseTabs(_ raw: String) -> [BrowserTab] {
        raw.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line in
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 2, !parts[1].isEmpty else { return nil }
                let url = parts[1]
                // Skip internal pages
                guard url.hasPrefix("http://") || url.hasPrefix("https://") else { return nil }
                return BrowserTab(title: parts[0], url: url)
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
