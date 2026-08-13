import AppKit
import ApplicationServices
import DeckKit
import Foundation

/// Handles emoji/text insertion actions from the deck.
/// The visual rain effect is handled separately by AgentModel.
@MainActor
struct TextInserter {
    var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func insert(_ text: String) -> Result<Void, ActionFailure> {
        guard !text.isEmpty else { return .failure(.notFound("Nothing to insert")) }
        return .success(())
    }
}
