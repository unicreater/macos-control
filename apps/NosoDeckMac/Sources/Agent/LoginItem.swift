import Foundation
import ServiceManagement

/// Start at login (FR-20).
///
/// `SMAppService.mainApp` is the sandbox-legal, MAS-shippable route — no helper bundle,
/// no login-item plist to install, and the user can also turn it off in System Settings
/// → General → Login Items, which is why the toggle reads the live status rather than
/// remembering what it last set.
@MainActor
struct LoginItem {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the failure reason, or nil on success.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// True when macOS is holding the registration until the user approves it in
    /// System Settings — worth saying out loud rather than looking broken.
    var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
}
