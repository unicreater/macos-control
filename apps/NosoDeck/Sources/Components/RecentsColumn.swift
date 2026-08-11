import DeckKit
import SwiftUI

/// S9 — the recents column (FR-16).
///
/// A 92pt column beside the grid, holding four cells. **The 4×2 grid does not shrink to
/// make room** — the column consumes the horizontal slack landscape provides, which is
/// the whole reason it exists here and not in portrait.
///
/// For free users it is a locked teaser that opens the paywall. Never a dead tap.
struct RecentsColumn: View {
    let bundleIDs: [String]
    let isUnlocked: Bool
    var iconProvider: (String) -> Image?
    var nameProvider: (String) -> String
    var onActivate: (String) -> Void
    var onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DeckSpace.s) {
            HStack(spacing: DeckSpace.xs) {
                Text("Recent")
                    .deckFont(.meta)
                    .foregroundStyle(DeckColor.inkMuted)
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(DeckColor.ochre)
                }
            }

            if isUnlocked {
                unlockedCells
            } else {
                teaser
            }

            Spacer(minLength: 0)
        }
        .frame(width: DeckGrid.recentsColumnWidth)
    }

    @ViewBuilder
    private var unlockedCells: some View {
        if bundleIDs.isEmpty {
            // Empty, not blank: it says why there is nothing here yet.
            Text("Apps you switch to on the Mac show up here.")
                .deckFont(.bodySmall)
                .foregroundStyle(DeckColor.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(bundleIDs.prefix(MacState.maxVisibleRecents), id: \.self) { bundleID in
                Button { onActivate(bundleID) } label: {
                    cell(bundleID: bundleID)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(nameProvider(bundleID))
                .accessibilityHint("Recently used. Activates on the Mac.")
            }
        }
    }

    private func cell(bundleID: String) -> some View {
        HStack(spacing: DeckSpace.s) {
            if let icon = iconProvider(bundleID) {
                icon.resizable().frame(width: 26, height: 26)
            } else {
                RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous)
                    .fill(Color(hex: 0x2C2C2C))
                    .frame(width: 26, height: 26)
            }
            Spacer(minLength: 0)
        }
        .padding(DeckSpace.s)
        .frame(maxWidth: .infinity)
        .background(DeckColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
        }
    }

    private var teaser: some View {
        Button(action: onUpgrade) {
            VStack(spacing: DeckSpace.s) {
                ForEach(0..<MacState.maxVisibleRecents, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                        .fill(DeckColor.surfaceRaised)
                        .frame(height: 42)
                        .overlay {
                            RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                                .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
                        }
                }
                Text("Premium")
                    .deckFont(.meta)
                    .foregroundStyle(DeckColor.ochre)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recent apps — requires Premium")
        .accessibilityHint("Opens the upgrade screen.")
    }
}
