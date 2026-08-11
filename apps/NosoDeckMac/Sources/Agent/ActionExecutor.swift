import AppKit
import DeckKit
import Foundation

/// Carries out what a tile tap asks for.
///
/// M4 implements app activation (FR-9). Quit arrives with M5, Shortcuts and URLs with
/// M6, and text insertion with M8; each returns a clear failure until then rather than
/// silently doing nothing.
struct ActionExecutor {
    func perform(_ request: ActionRequest) async -> Result<Void, ActionFailure> {
        switch request.kind {
        case .activateApp:
            return await activate(bundleID: request.target)
        case .quitApp:
            return .failure(.notImplemented("Quitting apps arrives in M5"))
        case .runShortcut:
            return .failure(.notImplemented("Shortcuts arrive in M6"))
        case .openURL:
            return .failure(.notImplemented("Website tiles arrive in M6"))
        case .insertText:
            return .failure(.notImplemented("Text insertion arrives in M8"))
        }
    }

    /// Launch if closed, bring to front if running — `openApplication` does both, which
    /// is why it is used in place of `NSRunningApplication.activate` and avoids that
    /// API's macOS 14 deprecation entirely.
    private func activate(bundleID: String) async -> Result<Void, ActionFailure> {
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
}

enum ActionFailure: Error {
    case notFound(String)
    case notImplemented(String)
    case systemError(String)

    /// What travels back in `actionResult.error` and, eventually, in front of the user.
    var message: String {
        switch self {
        case .notFound(let message), .notImplemented(let message), .systemError(let message):
            return message
        }
    }
}
