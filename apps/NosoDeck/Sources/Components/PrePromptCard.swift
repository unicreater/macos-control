import DeckKit
import SwiftUI

/// The card that precedes every system permission dialog (FR-24).
///
/// The pattern is fixed: *why · what breaks without it · the degraded path*, shown
/// **before** the system prompt. Local network is the only one whose honest degraded
/// path is "none", and saying so is better than inventing one.
struct PrePromptCard: View {
    let kind: PermissionKind
    var allowTitle: String = "Allow"
    let onAllow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            Text(label)
                .deckFont(.meta)
                .foregroundStyle(DeckColor.inkMuted)

            reason(title: "Why", detail: why)
            reason(title: "Without it", detail: withoutIt)
            reason(title: "Degraded path", detail: kind.degradedPath ?? "None — this one is required.")

            Button(action: onAllow) {
                Text(allowTitle)
                    .deckFont(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(DeckColor.onMint)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(DeckColor.mint, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(26)
        .background(DeckColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
                .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
        }
    }

    private func reason(title: String, detail: String) -> some View {
        // The label carries the weight and the detail carries the sentence, so the card
        // scans in one pass.
        Text("**\(title)** \(detail)")
            .deckFont(.bodySmall)
            .foregroundStyle(DeckColor.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var label: String {
        switch kind {
        case .localNetwork: return "Local network access"
        case .automation: return "Automation access"
        case .accessibility: return "Accessibility access"
        }
    }

    private var why: String {
        switch kind {
        case .localNetwork: return "to reach your Mac on this Wi-Fi."
        case .automation: return "to list and run your Mac's Shortcuts."
        case .accessibility: return "to type emoji into whatever you're writing on the Mac."
        }
    }

    private var withoutIt: String {
        switch kind {
        case .localNetwork: return "nothing connects at all."
        case .automation: return "Shortcuts tiles can't run."
        case .accessibility: return "emoji can't be typed for you."
        }
    }
}
