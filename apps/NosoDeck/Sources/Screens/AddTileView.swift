import DeckKit
import SwiftUI

/// S6 — add a tile.
///
/// Because a page holds only eight tiles, the picker has to say where the tile is going
/// and warn when that fills the page. The preview is a live keycap, so what you see is
/// literally the component that will land on the deck.
struct AddTileView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: AppCatalogEntry?
    @State private var label = ""

    var body: some View {
        HStack(alignment: .top, spacing: DeckSpace.xl) {
            picker
                .frame(maxWidth: .infinity)
            preview
                .frame(width: 280)
        }
        .padding(DeckSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckColor.chassis)
        .preferredColorScheme(.dark)
        .task {
            // M4 ships the apps tab; Shortcuts and Website arrive with M6.
            model.requestCatalog()
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            Text("Apps")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.ink)

            TextField("Search apps on your Mac", text: $query)
                .textFieldStyle(.plain)
                .deckFont(.body)
                .foregroundStyle(DeckColor.ink)
                .padding(.horizontal, DeckSpace.m)
                .frame(height: 38)
                .background(Color(hex: 0x141414), in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                        .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
                }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            results
        }
    }

    @ViewBuilder
    private var results: some View {
        let entries = model.searchResults(for: query)

        if entries.isEmpty {
            // Never a blank panel: say which of the two situations this is.
            VStack(alignment: .leading, spacing: DeckSpace.s) {
                Text(model.catalog.isEmpty ? "Waiting for your Mac's app list…" : "No apps match “\(query)”")
                    .deckFont(.bodySmall)
                    .foregroundStyle(DeckColor.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DeckSpace.xl)
        } else {
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(entries) { entry in
                        row(for: entry)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func row(for entry: AppCatalogEntry) -> some View {
        let isSelected = selection?.bundleID == entry.bundleID

        return Button {
            selection = entry
            label = entry.name
        } label: {
            HStack(spacing: DeckSpace.m) {
                if let icon = model.icons.image(forHash: entry.iconHash) {
                    icon.resizable().frame(width: 26, height: 26)
                } else {
                    RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous)
                        .fill(Color(hex: 0x2C2C2C))
                        .frame(width: 26, height: 26)
                }
                Text(entry.name)
                    .deckFont(.body)
                    .foregroundStyle(DeckColor.ink)
                    .lineLimit(1)
                Spacer(minLength: DeckSpace.s)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DeckColor.mint)
                }
            }
            .padding(.horizontal, DeckSpace.m)
            .frame(minHeight: 46)
            .background(DeckColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                    .strokeBorder(isSelected ? DeckColor.mint : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: DeckSpace.l) {
            Text("Preview")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.inkMuted)

            KeycapView(
                tile: previewTile,
                activity: .idle,
                icon: model.icons.image(forHash: selection?.iconHash)
            )
            .frame(width: 150, height: 112)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: DeckSpace.s) {
                Text("Label")
                    .deckFont(.meta)
                    .foregroundStyle(DeckColor.inkMuted)
                TextField("Label", text: $label)
                    .textFieldStyle(.plain)
                    .deckFont(.body)
                    .foregroundStyle(DeckColor.ink)
                    .padding(.horizontal, DeckSpace.m)
                    .frame(height: 38)
                    .background(Color(hex: 0x141414), in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                            .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
                    }
            }

            destination

            Spacer(minLength: 0)

            HStack(spacing: DeckSpace.m) {
                Button { dismiss() } label: {
                    Text("Cancel")
                        .deckFont(.body)
                        .foregroundStyle(DeckColor.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay {
                            RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                                .strokeBorder(Color(hex: 0x3A3A3A), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)

                Button(action: add) {
                    Text("Add")
                        .deckFont(.body)
                        .foregroundStyle(DeckColor.onMint)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(DeckColor.mint, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                // Stays visible but dimmed while unusable — never hidden.
                .opacity(canAdd ? 1 : 0.4)
                .disabled(!canAdd)
            }
        }
        .padding(20)
        .background(DeckColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
                .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
        }
    }

    /// Where it lands, and whether that fills the page. The picker must say both,
    /// because eight is a hard ceiling and running into it should never be a surprise.
    @ViewBuilder
    private var destination: some View {
        VStack(alignment: .leading, spacing: DeckSpace.xs) {
            Text("Goes to")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.inkMuted)

            if let slot = model.nextSlot {
                Text(slot.humanReadable)
                    .deckFont(.bodySmall)
                    .foregroundStyle(DeckColor.inkSecondary)
                if slot.slotIndex == Page.maxTiles - 1 {
                    Text("— page full after this")
                        .deckFont(.bodySmall)
                        .foregroundStyle(DeckColor.ochre)
                }
            } else {
                Text("Every page is full. Remove a tile, or add a page.")
                    .deckFont(.bodySmall)
                    .foregroundStyle(DeckColor.ochre)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var previewTile: Tile {
        Tile(
            target: .app(bundleID: selection?.bundleID ?? ""),
            label: label.isEmpty ? (selection?.name ?? "Tile") : label
        )
    }

    private var canAdd: Bool {
        selection != nil && model.nextSlot != nil && !label.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func add() {
        guard let selection else { return }
        model.add(Tile(
            target: .app(bundleID: selection.bundleID),
            label: label.trimmingCharacters(in: .whitespaces)
        ))
        dismiss()
    }
}
