import DeckKit
import SwiftUI

/// Folder popup — blurred background with floating keycap tiles.
/// Same visual language as the deck grid. Tap outside to dismiss.
struct FolderOverlay: View {
    let folder: TileFolder
    let model: AppModel
    let isLandscape: Bool
    let onDismiss: () -> Void

    private var columns: Int { min(folder.tiles.count, isLandscape ? 4 : 2) }

    var body: some View {
        ZStack {
            // Blurred background — tap to dismiss
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            GeometryReader { geo in
                let portraitW = geo.size.width
                let portraitH = geo.size.height
                let contentW = isLandscape ? portraitH : portraitW
                let contentH = isLandscape ? portraitW : portraitH

                VStack(spacing: DeckSpace.m) {
                    // Folder name
                    Text(folder.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DeckColor.ink)

                    if folder.tiles.isEmpty {
                        VStack(spacing: DeckSpace.s) {
                            Image(systemName: "folder")
                                .font(.system(size: 32))
                                .foregroundStyle(DeckColor.inkFaint)
                            Text("Drag tiles here in edit mode")
                                .deckFont(.bodySmall)
                                .foregroundStyle(DeckColor.inkMuted)
                        }
                        .frame(height: 120)
                    } else {
                        // Tile grid — same KeycapView as deck
                        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: DeckGrid.gutter), count: columns)
                        let tileSize: CGFloat = isLandscape
                            ? min((contentW - 80) / CGFloat(columns), 100)
                            : min((contentW - 60) / CGFloat(columns), 120)

                        LazyVGrid(columns: gridColumns, spacing: DeckGrid.gutter) {
                            ForEach(folder.tiles) { tile in
                                KeycapView(
                                    tile: tile,
                                    activity: model.activity(for: tile),
                                    icon: model.icon(for: tile),
                                    onTap: {
                                        model.activate(tile)
                                        onDismiss()
                                    }
                                )
                                .frame(width: tileSize, height: tileSize)
                            }
                        }
                    }
                }
                .padding(DeckSpace.xl)
                .frame(width: contentW * 0.75)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                }
                .frame(width: contentW, height: contentH)
                .if(isLandscape) { view in
                    view
                        .rotationEffect(.degrees(-90))
                        .frame(width: portraitW, height: portraitH)
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}
