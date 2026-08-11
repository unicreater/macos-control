import DeckKit
import SwiftUI

/// The connection pill in the deck's top bar, and the banners that replace it.
///
/// The rule from design S4: the deck is never blanked. Reconnecting desaturates it
/// behind a warning banner; disconnected drops it to 38% opacity behind a red one. In
/// both cases the tiles stay on screen — the user keeps their place.
struct ConnectionBanner: View {
    let state: ConnectionState
    let macName: String
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .connected(let latencyMs):
            HStack(spacing: DeckSpace.s) {
                Circle()
                    .fill(DeckColor.mint)
                    .frame(width: 9, height: 9)
                Text(latencyMs > 0 ? "\(macName) · \(latencyMs)ms" : macName)
                    .deckFont(.meta)
                    .foregroundStyle(DeckColor.inkMuted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Connected to \(macName)")

        case .connecting, .reconnecting:
            banner(
                text: state == .connecting ? "Connecting to \(macName)…" : "Reconnecting to \(macName)…",
                tint: DeckColor.ochre,
                background: DeckColor.surface,
                retry: nil
            )

        case .disconnected:
            banner(
                text: "Disconnected — tiles are inactive until your Mac is back.",
                tint: DeckColor.red,
                background: DeckColor.redBackground,
                retry: onRetry
            )
        }
    }

    private func banner(text: String, tint: Color, background: Color, retry: (() -> Void)?) -> some View {
        HStack(spacing: DeckSpace.s) {
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)
            Text(text)
                .deckFont(.bodySmall)
                .foregroundStyle(retry == nil ? DeckColor.inkSecondary : DeckColor.redInk)
            if let retry {
                Button("Retry", action: retry)
                    .deckFont(.bodySmall)
                    .foregroundStyle(DeckColor.redInk)
                    .underline()
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DeckSpace.m)
        .padding(.vertical, DeckSpace.s)
        .background(background, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                .strokeBorder(tint, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

extension ConnectionState {
    /// Design S4: the deck drops to 38% when the link is gone, and desaturates while
    /// it is coming back. Never to zero — the tiles stay visible either way.
    var deckOpacity: Double {
        switch self {
        case .connected: return 1
        case .connecting, .reconnecting: return 0.62
        case .disconnected: return 0.38
        }
    }
}
