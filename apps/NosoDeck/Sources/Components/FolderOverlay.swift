import DeckKit
import SwiftUI

/// Overlay showing a folder's contents as a mini grid.
/// Tap a tile inside to activate it, tap outside to close.
struct FolderOverlay: View {
    let folder: TileFolder
    let model: AppModel
    let onDismiss: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: DeckSpace.s), count: 2)

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
                .ignoresSafeArea()

            VStack(spacing: DeckSpace.m) {
                Text(folder.name)
                    .deckFont(.title)
                    .foregroundStyle(DeckColor.ink)

                if folder.tiles.isEmpty {
                    VStack(spacing: DeckSpace.s) {
                        Image(systemName: "folder")
                            .font(.system(size: 28))
                            .foregroundStyle(DeckColor.inkFaint)
                        Text("Empty folder")
                            .deckFont(.bodySmall)
                            .foregroundStyle(DeckColor.inkMuted)
                    }
                    .padding(.vertical, DeckSpace.xl)
                } else {
                    LazyVGrid(columns: columns, spacing: DeckSpace.s) {
                        ForEach(folder.tiles) { tile in
                            Button {
                                model.activate(tile)
                            } label: {
                                VStack(spacing: 4) {
                                    folderTileIcon(tile)
                                        .frame(width: 48, height: 48)
                                    Text(tile.label)
                                        .deckFont(.meta)
                                        .foregroundStyle(DeckColor.inkMuted)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DeckSpace.s)
                                .background(DeckColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                                        .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("Drag tiles onto this folder in edit mode to add them")
                    .deckFont(.meta)
                    .foregroundStyle(DeckColor.inkFaint)
                    .multilineTextAlignment(.center)

                Button { onDismiss() } label: {
                    Text("Done")
                        .deckFont(.body)
                        .foregroundStyle(DeckColor.inkMuted)
                        .frame(maxWidth: 100, minHeight: 36)
                        .overlay {
                            Capsule().strokeBorder(Color(hex: 0x3A3A3A), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(DeckSpace.xl)
            .background(DeckColor.chassis, in: RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            }
            .padding(.horizontal, DeckSpace.xl)
        }
    }

    @ViewBuilder
    private func folderTileIcon(_ tile: Tile) -> some View {
        if let emoji = tile.emoji, !emoji.isEmpty {
            Text(emoji).font(.system(size: 28))
        } else if let icon = model.icon(for: tile) {
            icon.resizable().aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: "app")
                .font(.system(size: 24))
                .foregroundStyle(DeckColor.inkMuted)
        }
    }
}
