import DeckKit
import SwiftUI

/// Folder popup — full 4x2 / 2x4 grid identical to the main deck.
/// Tiles activate apps without closing the folder. Tapping a frontmost
/// app opens the radial menu. Tap outside the grid to dismiss.
struct FolderOverlay: View {
    let folder: TileFolder
    let model: AppModel
    let isLandscape: Bool
    let onDismiss: () -> Void

    @State private var showRadialMenu = false

    private var gridRows: Int { isLandscape ? DeckGrid.rows : DeckGrid.rows(isPortrait: true) }
    private var gridColumns: Int { isLandscape ? DeckGrid.columns : DeckGrid.columns(isPortrait: true) }

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

                ZStack {
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
                            // Same 4x2 / 2x4 grid as main deck
                            VStack(spacing: DeckGrid.gutter) {
                                ForEach(0..<gridRows, id: \.self) { row in
                                    HStack(spacing: DeckGrid.gutter) {
                                        ForEach(0..<gridColumns, id: \.self) { column in
                                            let slot = row * gridColumns + column
                                            folderCell(slot: slot)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(DeckSpace.xl)
                    .frame(width: contentW * 0.85)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    }

                    if showRadialMenu {
                        ControlPanelView(
                            model: model,
                            isLandscape: isLandscape,
                            skipRotation: true,
                            onDismiss: { showRadialMenu = false }
                        )
                        .frame(width: contentW, height: contentH)
                        .transition(.opacity)
                    }
                }
                .frame(width: contentW, height: contentH)
                .if(isLandscape) { view in
                    view
                        .rotationEffect(.degrees(-90))
                        .frame(width: portraitW, height: portraitH)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showRadialMenu)
    }

    @ViewBuilder
    private func folderCell(slot: Int) -> some View {
        if slot < folder.tiles.count {
            let tile = folder.tiles[slot]
            KeycapView(
                tile: tile,
                activity: model.activity(for: tile),
                icon: model.icon(for: tile),
                onTap: {
                    if model.activity(for: tile) == .frontmost {
                        showRadialMenu = true
                    } else {
                        model.activate(tile)
                    }
                }
            )
        } else {
            // Empty slot — same style as deck
            EmptySlotView {}
                .allowsHitTesting(false)
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}
