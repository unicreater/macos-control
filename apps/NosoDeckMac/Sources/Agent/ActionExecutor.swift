import AppKit
import DeckKit
import Foundation

/// Carries out what a tile tap asks for.
///
/// Text insertion arrives in M8 and returns a clear failure until then, rather than
/// silently doing nothing.
@MainActor
struct ActionExecutor {
    private let shortcuts = ShortcutsBridge()

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
            return .failure(.notImplemented("Text insertion arrives in M8"))
        }
    }

    /// Opens in the Mac's default browser and brings it forward (FR-14).
    private func openURL(_ raw: String) -> Result<Void, ActionFailure> {
        guard TileTarget.isValidWebsiteURL(raw), let url = URL(string: raw.trimmingCharacters(in: .whitespaces)) else {
            return .failure(.notFound("“\(raw)” isn't a valid web address"))
        }
        guard NSWorkspace.shared.open(url) else {
            return .failure(.systemError("Nothing on this Mac could open that address"))
        }
        return .success(())
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
