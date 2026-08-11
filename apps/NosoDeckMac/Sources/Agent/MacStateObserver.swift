import AppKit
import DeckKit
import Foundation

/// Watches what the Mac is doing and reports every change (FR-10).
///
/// This is what makes the deck live rather than a launcher. `NSWorkspace` posts launch,
/// terminate and activate notifications; each one produces a fresh snapshot, and the
/// agent pushes it to every paired phone. No polling — the phone's tiles change because
/// the Mac changed, not because a timer fired.
@MainActor
final class MacStateObserver {
    var onChange: ((MacState) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private(set) var current = MacState.unknown

    func start() {
        stop()

        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]

        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.handle(notification, name: name)
                }
            }
            observers.append(observer)
        }

        current = snapshot(recents: [])
        onChange?(current)
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    deinit {
        // `observers` cannot be touched from a nonisolated deinit; the agent calls
        // stop() on termination, and the process is going away regardless.
    }

    private func handle(_ notification: Notification, name: Notification.Name) {
        var recents = current.recents

        // Activation order is the only thing notifications tell us that a snapshot
        // cannot, so it is accumulated here rather than recomputed (FR-16).
        if name == NSWorkspace.didActivateApplicationNotification,
           let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let bundleID = app.bundleIdentifier,
           bundleID != Bundle.main.bundleIdentifier {
            var updated = current
            updated.recordActivation(of: bundleID)
            recents = updated.recents
        }

        if name == NSWorkspace.didTerminateApplicationNotification,
           let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let bundleID = app.bundleIdentifier {
            recents.removeAll { $0 == bundleID }
        }

        let updated = snapshot(recents: recents)
        guard updated != current else { return }
        current = updated
        onChange?(updated)
    }

    /// Only `.regular` apps: agents and daemons are not things anyone puts on a deck,
    /// and NosoDeck itself is never reported.
    private func snapshot(recents: [String]) -> MacState {
        var running: Set<String> = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier else { continue }
            running.insert(bundleID)
        }

        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return MacState(
            running: running,
            frontmost: frontmost == Bundle.main.bundleIdentifier ? nil : frontmost,
            // A recent app that has since quit is dropped, so the column never offers
            // something that is no longer there.
            recents: recents.filter { running.contains($0) }
        )
    }
}
