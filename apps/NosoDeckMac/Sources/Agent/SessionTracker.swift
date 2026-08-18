import AppKit
import Darwin
import DeckKit
import Foundation

/// Detects session states within specific apps by inspecting process trees
/// and (where trusted) the Accessibility API.
///
/// Warp: process tree analysis — each shell under the terminal-server is a session.
/// Claude/ChatGPT: Accessibility API — reads UI state to determine if AI is responding.
@MainActor
final class SessionTracker {
    private var dispatchTimer: DispatchSourceTimer?
    var onChange: (([AppSessionInfo]) -> Void)?

    private(set) var current: [AppSessionInfo] = []
    /// Cache last successful AX reads since Electron apps only expose AX when focused.
    private var cachedClaudeSessions: [AppSession]?
    private var hasScannedClaude = false

    // Bundle IDs we track
    private static let warpBundleID = "dev.warp.Warp-Stable"
    private static let claudeBundleID = "com.anthropic.claudefordesktop"
    private static let chatGPTBundleID = "com.openai.chat"

    func start() {
        stop()
        let queue = DispatchQueue(label: "nosodeck.sessions", qos: .utility)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 3)
        t.setEventHandler { [weak self] in
            let infos = Self.scanSessionsSync()
            DispatchQueue.main.async {
                self?.applyResults(infos)
            }
        }
        t.resume()
        self.dispatchTimer = t
    }

    /// Synchronous, nonisolated — safe to call from a GCD queue.
    nonisolated private static func scanSessionsSync() -> [AppSessionInfo] {
            var infos: [AppSessionInfo] = []

            let procs = Self.runPS()
            let warpWindows = Self.getWarpWindows()

            let warpProcs = procs.filter { $0.command.contains("Warp.app") }
            if !warpProcs.isEmpty {
                let warpPIDSet = Set(warpProcs.map(\.pid))
                let shells = ["zsh", "bash", "fish", "sh", "tcsh", "ksh"]
                let shellProcs = procs.filter { proc in
                    warpPIDSet.contains(proc.ppid) &&
                    shells.contains(where: { s in proc.shortName.contains(s) })
                }

                var sessions: [AppSession] = []
                for shell in shellProcs {
                    let children = procs.filter { $0.ppid == shell.pid }

                    // Try to find a matching window for this session
                    // Warp window names contain project dir and session context
                    let matchedWindow = warpWindows.first { win in
                        // Match by checking if shell PID appears in window hierarchy
                        // or match by window name context
                        win.isReal
                    }

                    // Find next unassigned window
                    let usedWinIDs = Set(sessions.compactMap(\.windowID))
                    let nextWindow = warpWindows.first(where: { w in w.isReal && !usedWinIDs.contains(w.windowNumber) })

                    if children.isEmpty {
                        let label = nextWindow?.projectName ?? "Terminal"
                        sessions.append(AppSession(
                            id: "\(shell.pid)",
                            label: label,
                            status: .idle,
                            detail: "Ready",
                            windowID: nextWindow?.windowNumber
                        ))
                    } else {
                        let cmd = children.first!.shortName
                        let label = nextWindow?.projectName ?? cmd

                        // Detect status from descendant processes:
                        // - caffeinate present = claude is actively running (keeps system awake)
                        // - sourcekit-lsp, swift-frontend etc = specific tool running
                        // - NO descendants at all = truly waiting for user input
                        let allDescendants = Self.descendants(of: children.map(\.pid), in: procs)
                        let hasCaffeinate = allDescendants.contains { $0.shortName == "caffeinate" }
                        let toolProcesses: Set<String> = ["caffeinate", "sleep", "cat"]
                        let activeTools = allDescendants.filter { !toolProcesses.contains($0.shortName) }

                        let status: AppSession.Status
                        let detail: String
                        if !activeTools.isEmpty {
                            // Specific tools running (compiling, reading files, etc.)
                            status = .busy
                            detail = activeTools.prefix(2).map(\.shortName).joined(separator: ", ")
                        } else if hasCaffeinate {
                            // caffeinate = claude is processing (API calls, thinking)
                            status = .busy
                            detail = "Running"
                        } else {
                            // No descendants = truly idle, waiting for user
                            status = .done
                            detail = "Needs input"
                        }

                        sessions.append(AppSession(
                            id: "\(shell.pid)",
                            label: label,
                            status: status,
                            detail: detail,
                            windowID: nextWindow?.windowNumber
                        ))
                    }
                }
                if !sessions.isEmpty {
                    infos.append(AppSessionInfo(bundleID: warpBundleID, sessions: sessions))
                }
            }

            // Claude and ChatGPT are detected via Accessibility on the main thread
            // (added in applyResults via axSessions)

            return infos
    }

    /// Reads Claude/ChatGPT sessions from the Accessibility tree (must run on main thread).
    private func readAXSessions() -> [AppSessionInfo] {
        guard AXIsProcessTrusted() else { return [] }
        var infos: [AppSessionInfo] = []

        if let claude = readClaudeSessions() { infos.append(claude) }
        if let chatgpt = readChatGPTSessions() { infos.append(chatgpt) }

        return infos
    }

    private func readClaudeSessions() -> AppSessionInfo? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.claudeBundleID).first else {
            cachedClaudeSessions = nil
            hasScannedClaude = false
            return nil
        }

        // Briefly activate Claude once to populate the AX tree
        if !hasScannedClaude && cachedClaudeSessions == nil {
            hasScannedClaude = true
            let previousApp = NSWorkspace.shared.frontmostApplication
            app.activate(options: .activateAllWindows)
            Thread.sleep(forTimeInterval: 1.5)
            // Re-activate the previous frontmost app
            previousApp?.activate(options: .activateAllWindows)
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        guard let windows = windowsRef as? [AXUIElement], let win = windows.first else {
            // Electron AX not available (app not focused) — use cached sessions
            if let cached = cachedClaudeSessions {
                return AppSessionInfo(bundleID: Self.claudeBundleID, sessions: cached)
            }
            return AppSessionInfo(bundleID: Self.claudeBundleID, sessions: [
                AppSession(id: Self.claudeBundleID, label: "Claude", status: .idle)
            ])
        }

        // Find the Sidebar by description
        guard let sidebar = findElementByDesc(win, desc: "Sidebar", maxDepth: 10) else {
            return AppSessionInfo(bundleID: Self.claudeBundleID, sessions: [
                AppSession(id: Self.claudeBundleID, label: "Claude", status: .idle)
            ])
        }

        // Collect session buttons from sidebar — they have titles like "Idle Loop implementation"
        var sessions: [AppSession] = []
        collectSessionButtons(sidebar, into: &sessions, depth: 0)

        if sessions.isEmpty {
            sessions.append(AppSession(id: Self.claudeBundleID, label: "Claude", status: .idle))
        }

        // Cache successful read for when Claude loses focus
        cachedClaudeSessions = sessions

        return AppSessionInfo(bundleID: Self.claudeBundleID, sessions: sessions)
    }

    private func collectSessionButtons(_ el: AXUIElement, into sessions: inout [AppSession], depth: Int) {
        guard depth < 10, sessions.count < 8 else { return }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef)

        let role = roleRef as? String ?? ""
        let title = titleRef as? String ?? ""

        // Session buttons have titles like "Idle Choclift Swift macOS/iOS implementation"
        // Skip navigation buttons (Today, Aug 12, Older, New, etc.)
        let navButtons = ["Today", "New", "Artifacts", "Customize", "Older", "Home", "Code"]
        if role == "AXButton" && !title.isEmpty
            && !navButtons.contains(title)
            && !title.hasPrefix("Aug ") && !title.hasPrefix("Jul ")
            && !title.hasPrefix("Jun ") && !title.hasPrefix("May ")
            && !title.hasPrefix("Show ") {

            // Parse status from title prefix
            // Claude uses "Idle" for inactive and "Running" for active sessions
            let status: AppSession.Status
            var label = title
            if title.hasPrefix("Running ") {
                status = .busy
                label = String(title.dropFirst(8))
            } else if title.hasPrefix("Idle ") {
                status = .idle
                label = String(title.dropFirst(5))
            } else {
                status = .idle
            }

            sessions.append(AppSession(
                id: "claude.\(sessions.count)",
                label: label,
                status: status
            ))
        }

        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef)
        for child in (childrenRef as? [AXUIElement]) ?? [] {
            collectSessionButtons(child, into: &sessions, depth: depth + 1)
        }
    }

    private func readChatGPTSessions() -> AppSessionInfo? {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Self.chatGPTBundleID).first != nil else { return nil }
        // ChatGPT's Electron AX tree doesn't expose buttons well
        return AppSessionInfo(bundleID: Self.chatGPTBundleID, sessions: [
            AppSession(id: Self.chatGPTBundleID, label: "ChatGPT", status: .idle)
        ])
    }

    private func findElementByDesc(_ el: AXUIElement, desc: String, maxDepth: Int) -> AXUIElement? {
        guard maxDepth > 0 else { return nil }
        var d: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &d)
        if (d as? String) == desc { return el }
        var c: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &c)
        for child in (c as? [AXUIElement]) ?? [] {
            if let found = findElementByDesc(child, desc: desc, maxDepth: maxDepth - 1) { return found }
        }
        return nil
    }

    /// Gets process list using sysctl — no subprocess spawning needed.
    nonisolated private static func runPS() -> [ProcessEntry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size: Int = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else { return [] }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride
        var results: [ProcessEntry] = []

        for i in 0..<actualCount {
            let proc = procs[i]
            let pid = proc.kp_proc.p_pid
            let ppid = proc.kp_eproc.e_ppid

            // Get the full path via proc_pidpath
            var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let pathLen = proc_pidpath(pid, &pathBuf, UInt32(MAXPATHLEN))

            let command: String
            if pathLen > 0 {
                command = String(cString: pathBuf)
            } else {
                command = withUnsafePointer(to: proc.kp_proc.p_comm) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                        String(cString: $0)
                    }
                }
            }

            // p_comm is the short process name (e.g. "claude", "node", "zsh")
            let processName = withUnsafePointer(to: proc.kp_proc.p_comm) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                    String(cString: $0)
                }
            }

            results.append(ProcessEntry(pid: pid, ppid: ppid, cpu: 0, command: command, processName: processName))
        }
        return results
    }

    /// Recursively finds all descendant processes of the given PIDs.
    nonisolated private static func descendants(of pids: [Int32], in procs: [ProcessEntry]) -> [ProcessEntry] {
        var result: [ProcessEntry] = []
        var queue = pids
        while !queue.isEmpty {
            let parentPID = queue.removeFirst()
            let children = procs.filter { $0.ppid == parentPID }
            result.append(contentsOf: children)
            queue.append(contentsOf: children.map(\.pid))
        }
        return result
    }

    private struct WarpWindow {
        let windowNumber: Int
        let name: String
        let isOnScreen: Bool
        /// Real content windows (not menu bar items)
        var isReal: Bool { !name.isEmpty }
        /// Extract the project directory name from window title like "content-creation-workflow · ..."
        var projectName: String {
            let parts = name.components(separatedBy: " · ")
            return parts.first?.trimmingCharacters(in: .whitespaces) ?? name
        }
    }

    nonisolated private static func getWarpWindows() -> [WarpWindow] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windowList.compactMap { w -> WarpWindow? in
            guard (w["kCGWindowOwnerName"] as? String)?.contains("Warp") == true,
                  (w["kCGWindowLayer"] as? Int) == 0 else { return nil }
            let name = w["kCGWindowName"] as? String ?? ""
            let num = w["kCGWindowNumber"] as? Int ?? 0
            let onScreen = w["kCGWindowIsOnscreen"] as? Bool ?? false
            // Skip tiny windows (menu bar items)
            let bounds = w["kCGWindowBounds"] as? [String: Any] ?? [:]
            let height = bounds["Height"] as? Double ?? 0
            guard height > 100 else { return nil }
            return WarpWindow(windowNumber: num, name: name, isOnScreen: onScreen)
        }
    }

    private struct ProcessEntry {
        let pid: Int32, ppid: Int32, cpu: Double, command: String, processName: String

        /// A readable short name for display. Handles cases where the binary is
        /// named with a version number (e.g. claude-code's "2.1.81").
        var shortName: String {
            // Check known path patterns first
            let knownTools: [(pattern: String, name: String)] = [
                ("claude/versions", "claude"),
                ("claude-code", "claude"),
                ("Cellar/node", "node"),
                ("nvm/versions", "node"),
            ]
            for tool in knownTools {
                if command.contains(tool.pattern) { return tool.name }
            }

            // Use p_comm if it's not a version number
            if !processName.isEmpty && !processName.allSatisfy({ $0.isNumber || $0 == "." }) {
                return processName
            }

            // Last resort: walk up the path to find a meaningful name
            let components = command.components(separatedBy: "/")
            for component in components.reversed() {
                if !component.isEmpty && !component.allSatisfy({ $0.isNumber || $0 == "." }) {
                    return component
                }
            }
            return processName.isEmpty ? "unknown" : processName
        }
    }

    func stop() {
        dispatchTimer?.cancel()
        dispatchTimer = nil
    }

    /// Runs off the main thread — only uses process inspection, no AppKit UI.
    nonisolated private func pollBackground() -> [AppSessionInfo] {
        var infos: [AppSessionInfo] = []

        if let warp = warpSessionsBackground() {
            infos.append(warp)
        }
        // Claude/ChatGPT Accessibility detection needs main thread — skip in background.
        // Just report running/not-running for now.
        if isRunningSync(Self.claudeBundleID) {
            infos.append(AppSessionInfo(bundleID: Self.claudeBundleID, sessions: [
                AppSession(id: Self.claudeBundleID, label: "Claude", status: .idle)
            ]))
        }
        if isRunningSync(Self.chatGPTBundleID) {
            infos.append(AppSessionInfo(bundleID: Self.chatGPTBundleID, sessions: [
                AppSession(id: Self.chatGPTBundleID, label: "ChatGPT", status: .idle)
            ]))
        }

        return infos
    }

    private func applyResults(_ infos: [AppSessionInfo]) {
        // Merge process-based sessions (Warp) with AX-based sessions (Claude/ChatGPT)
        var merged = infos
        let axSessions = readAXSessions()
        merged.append(contentsOf: axSessions)

        guard merged != current else { return }
        current = merged
        onChange?(merged)
    }

    // MARK: - Warp (process tree)

    nonisolated private func warpSessionsBackground() -> AppSessionInfo? {
        guard isRunningSync(Self.warpBundleID) else { return nil }

        let allProcs = allProcesses()

        // Find Warp main PIDs by command path
        let warpPIDs = Set(allProcs.filter { $0.command.contains("Warp.app/Contents/MacOS") && !$0.command.contains("terminal-server") }.map(\.pid))
        guard !warpPIDs.isEmpty else { return nil }

        return buildWarpSessions(warpPIDs: warpPIDs, allProcs: allProcs)
    }

    private func warpSessions() -> AppSessionInfo? {
        guard isRunning(Self.warpBundleID) else { return nil }

        let warpPIDs = pidsForBundleID(Self.warpBundleID)
        guard !warpPIDs.isEmpty else { return nil }

        let allProcs = allProcesses()
        return buildWarpSessions(warpPIDs: warpPIDs, allProcs: allProcs)
    }

    nonisolated private func buildWarpSessions(warpPIDs: Set<Int32>, allProcs: [ProcessInfo]) -> AppSessionInfo? {
        // Find terminal-server
        let serverPID = allProcs.first { proc in
            warpPIDs.contains(proc.ppid) && proc.command.contains("terminal-server")
        }?.pid

        guard let serverPID else { return nil }

        // Each shell directly under terminal-server is a session
        let shells = allProcs.filter { $0.ppid == serverPID && isShell($0.command) }
        var sessions: [AppSession] = []

        for shell in shells {
            let children = allProcs.filter { $0.ppid == shell.pid }
            if children.isEmpty {
                sessions.append(AppSession(
                    id: "\(shell.pid)",
                    label: "Terminal",
                    status: .idle
                ))
            } else {
                let topChild = children.first!
                let cmdName = shortCommandName(topChild.command)
                let totalCPU = children.reduce(0.0) { $0 + $1.cpu }

                // If CPU is very low and process is sleeping, it might be done/waiting
                let status: AppSession.Status = totalCPU < 0.5 ? .done : .busy

                sessions.append(AppSession(
                    id: "\(shell.pid)",
                    label: cmdName,
                    status: status,
                    detail: cmdName,
                    cpuPercent: totalCPU
                ))
            }
        }

        return AppSessionInfo(bundleID: Self.warpBundleID, sessions: sessions)
    }

    // MARK: - Electron apps (Claude, ChatGPT) via Accessibility

    private func electronAppSessions(bundleID: String, appName: String) -> AppSessionInfo? {
        guard isRunning(bundleID) else { return nil }
        guard AXIsProcessTrusted() else {
            // Without Accessibility trust, we can only report running/not
            return AppSessionInfo(bundleID: bundleID, sessions: [
                AppSession(id: bundleID, label: appName, status: .idle, detail: "Grant Accessibility for session tracking")
            ])
        }

        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return nil
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)

        guard let windows = windowsRef as? [AXUIElement] else {
            return AppSessionInfo(bundleID: bundleID, sessions: [
                AppSession(id: bundleID, label: appName, status: .idle)
            ])
        }

        var sessions: [AppSession] = []
        for (i, window) in windows.enumerated() {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String) ?? appName

            // Try to detect if the app is actively generating a response by
            // looking for common UI patterns in the accessibility tree
            let status = detectElectronState(window: window)

            sessions.append(AppSession(
                id: "\(bundleID).\(i)",
                label: title.isEmpty ? appName : title,
                status: status
            ))
        }

        if sessions.isEmpty {
            sessions.append(AppSession(id: bundleID, label: appName, status: .idle))
        }

        return AppSessionInfo(bundleID: bundleID, sessions: sessions)
    }

    /// Inspects the Accessibility tree of an Electron window to detect AI state.
    /// Looks for "Stop" buttons (= AI generating), text areas with content, etc.
    private func detectElectronState(window: AXUIElement) -> AppSession.Status {
        // Search for a "Stop" button which indicates AI is generating
        if findElement(in: window, role: "AXButton", titleContains: "Stop", maxDepth: 8) {
            return .busy
        }
        // A "Send" button that's enabled means waiting for user input
        if findElement(in: window, role: "AXButton", titleContains: "Send", maxDepth: 8) {
            return .idle
        }
        return .idle
    }

    /// Recursively searches the accessibility tree for an element matching criteria.
    private func findElement(in element: AXUIElement, role: String, titleContains: String, maxDepth: Int) -> Bool {
        guard maxDepth > 0 else { return false }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)

        let currentRole = roleRef as? String ?? ""
        let currentTitle = (titleRef as? String ?? "") + (descRef as? String ?? "")

        if currentRole == role && currentTitle.localizedCaseInsensitiveContains(titleContains) {
            return true
        }

        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard let children = childrenRef as? [AXUIElement] else { return false }

        for child in children {
            if findElement(in: child, role: role, titleContains: titleContains, maxDepth: maxDepth - 1) {
                return true
            }
        }
        return false
    }

    // MARK: - Helpers

    private struct ProcessInfo {
        let pid: Int32
        let ppid: Int32
        let stat: String
        let cpu: Double
        let command: String
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Check if an app is running without needing MainActor — uses process list.
    nonisolated private func isRunningSync(_ bundleID: String) -> Bool {
        let appPaths: [String: String] = [
            "dev.warp.Warp-Stable": "Warp.app",
            "com.anthropic.claudefordesktop": "Claude.app",
            "com.openai.chat": "ChatGPT.app",
        ]
        guard let path = appPaths[bundleID] else { return false }
        let procs = allProcesses()
        return procs.contains { $0.command.contains(path) }
    }

    private func pidsForBundleID(_ bundleID: String) -> Set<Int32> {
        Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier))
    }

    nonisolated private func allProcesses() -> [ProcessInfo] {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,ppid,stat,%cpu,command"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output.components(separatedBy: "\n").dropFirst().compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard parts.count >= 5,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]),
                  let cpu = Double(parts[3]) else { return nil }
            let command = parts[4...].joined(separator: " ")
            return ProcessInfo(pid: pid, ppid: ppid, stat: parts[2], cpu: cpu, command: command)
        }
    }

    nonisolated private func isShell(_ command: String) -> Bool {
        let shells = ["zsh", "bash", "fish", "sh", "tcsh", "ksh"]
        return shells.contains { command.contains($0) }
    }

    nonisolated private func shortCommandName(_ command: String) -> String {
        let path = command.components(separatedBy: " ").first ?? command
        let name = (path as NSString).lastPathComponent
        // Strip leading dashes (login shells)
        return name.hasPrefix("-") ? String(name.dropFirst()) : name
    }
}
