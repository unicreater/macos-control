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

    // Bundle IDs we track
    private static let warpBundleID = "dev.warp.Warp-Stable"
    private static let claudeBundleID = "com.anthropic.claudefordesktop"
    private static let chatGPTBundleID = "com.openai.chat"

    func start() {
        stop()
        NSLog("[MacAgent] SessionTracker starting")
        let queue = DispatchQueue(label: "nosodeck.sessions", qos: .utility)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 3)
        t.setEventHandler { [weak self] in
            NSLog("[MacAgent] Timer fired, scanning...")
            let infos = Self.scanSessionsSync()
            NSLog("[MacAgent] Scan done: %d results", infos.count)
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

            // Warp: find all processes from Warp.app, then find shells whose parent
            // is a Warp process (the terminal-server). Since proc_pidpath returns
            // the same binary for both main and server, we identify the server by
            // finding the Warp process whose children are shells.
            let warpProcs = procs.filter { $0.command.contains("Warp.app") }
            if !warpProcs.isEmpty {
                let warpPIDSet = Set(warpProcs.map(\.pid))
                // Shells whose parent is any Warp process
                let shells = ["zsh", "bash", "fish", "sh", "tcsh", "ksh"]
                let shellProcs = procs.filter { proc in
                    warpPIDSet.contains(proc.ppid) &&
                    shells.contains(where: { s in proc.shortName.contains(s) })
                }

                var sessions: [AppSession] = []
                for shell in shellProcs {
                    let children = procs.filter { $0.ppid == shell.pid }
                    if children.isEmpty {
                        sessions.append(AppSession(id: "\(shell.pid)", label: "Terminal", status: .idle))
                    } else {
                        let cmd = children.first!.shortName
                        sessions.append(AppSession(id: "\(shell.pid)", label: cmd, status: .busy, detail: cmd, cpuPercent: 0))
                    }
                }
                if !sessions.isEmpty {
                    infos.append(AppSessionInfo(bundleID: warpBundleID, sessions: sessions))
                }
            }

            // Claude
            if procs.contains(where: { $0.command.contains("Claude.app") }) {
                infos.append(AppSessionInfo(bundleID: claudeBundleID, sessions: [
                    AppSession(id: claudeBundleID, label: "Claude", status: .idle)
                ]))
            }

            // ChatGPT
            if procs.contains(where: { $0.command.contains("ChatGPT.app") }) {
                infos.append(AppSessionInfo(bundleID: chatGPTBundleID, sessions: [
                    AppSession(id: chatGPTBundleID, label: "ChatGPT", status: .idle)
                ]))
            }

            return infos
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

            results.append(ProcessEntry(pid: pid, ppid: ppid, cpu: 0, command: command))
        }
        return results
    }

    private struct ProcessEntry {
        let pid: Int32, ppid: Int32, cpu: Double, command: String
        var shortName: String {
            (command as NSString).lastPathComponent
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
        NSLog("[MacAgent] applyResults called with %d infos", infos.count)
        for info in infos {
            NSLog("[MacAgent]   %@: %d sessions", info.bundleID, info.sessions.count)
        }
        guard infos != current else { return }
        current = infos
        onChange?(infos)
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
