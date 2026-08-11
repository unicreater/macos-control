import DeckKit
import SwiftUI

/// S4 and S5 — the deck itself, and its edit mode.
///
/// One gesture per region, as the handoff insists: tap a tile to activate, horizontal
/// swipe to change page, long-press to edit. Nothing competes on the same surface.
struct DeckView: View {
    let model: AppModel

    @State private var isConfirmingUnpair = false
    @State private var isAddingTile = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.bottom, 14)

            pages
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(model.session.state.deckOpacity)
                .disabled(!model.session.acceptsActions && !model.isEditing)
                .animation(reduceMotion ? nil : DeckMotion.stateChange, value: model.session.state)

            bottomBar
                .padding(.top, DeckSpace.m)
        }
        .padding(.top, DeckGrid.topPadding)
        .padding(.bottom, DeckGrid.bottomPadding)
        .padding(.horizontal, DeckSpace.safeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckColor.chassis)
        .sheet(isPresented: $isAddingTile) {
            AddTileView(model: model)
        }
        .confirmationDialog(
            "Unpair \(model.connectedMacName ?? "this Mac")?",
            isPresented: $isConfirmingUnpair,
            titleVisibility: .visible
        ) {
            Button("Unpair", role: .destructive) { model.unpairCurrentMac() }
            Button("Keep paired", role: .cancel) {}
        } message: {
            Text("Your deck layout stays on this iPhone. You'll need a new PIN to reconnect.")
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private var topBar: some View {
        if model.isEditing {
            HStack(spacing: DeckSpace.m) {
                Text("Editing page \(model.currentPage + 1)")
                    .deckFont(.meta)
                    .foregroundStyle(DeckColor.inkMuted)
                Spacer()
                Button { model.toggleEditing() } label: {
                    Text("Done")
                        .deckFont(.legend)
                        .foregroundStyle(DeckColor.onMint)
                        .padding(.horizontal, DeckSpace.l)
                        .frame(height: 34)
                        .background(DeckColor.mint, in: RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: DeckSpace.m) {
                ConnectionBanner(
                    state: model.session.state,
                    macName: model.connectedMacName ?? "Mac",
                    onRetry: { model.beginDiscovery() }
                )
                Spacer(minLength: DeckSpace.s)

                if let error = model.lastActionError {
                    Text(error)
                        .deckFont(.bodySmall)
                        .foregroundStyle(DeckColor.redInk)
                        .lineLimit(1)
                }

                Button { isConfirmingUnpair = true } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(DeckColor.inkMuted)
                        .frame(width: 36, height: 36)
                        .background(Color(hex: 0x1C1C1C), in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                                .strokeBorder(Color(hex: 0x2C2C2C), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: DeckSpace.s) {
            Spacer()
            ForEach(0..<model.pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == model.currentPage ? DeckColor.ink : Color(hex: 0x333333))
                    .frame(width: 22, height: 5)
                    .onTapGesture { model.setPage(index) }
            }
            Spacer()
        }
        .accessibilityLabel("Page \(model.currentPage + 1) of \(model.pageCount)")
    }

    // MARK: - Grid

    private var pages: some View {
        TabView(selection: pageBinding) {
            ForEach(0..<model.pageCount, id: \.self) { pageIndex in
                grid(pageIndex: pageIndex)
                    .tag(pageIndex)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func grid(pageIndex: Int) -> some View {
        let page = model.deck.pages[pageIndex]

        return VStack(spacing: DeckGrid.gutter) {
            ForEach(0..<DeckGrid.rows, id: \.self) { row in
                HStack(spacing: DeckGrid.gutter) {
                    ForEach(0..<DeckGrid.columns, id: \.self) { column in
                        let slot = row * DeckGrid.columns + column
                        cell(page: page, pageIndex: pageIndex, slot: slot)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(page: Page, pageIndex: Int, slot: Int) -> some View {
        if slot < page.tiles.count {
            let tile = page.tiles[slot]
            let keycap = KeycapView(
                tile: tile,
                activity: model.activity(for: tile),
                isEditing: model.isEditing,
                editIndex: slot,
                icon: model.icon(for: tile),
                // A long press flips edit mode while the finger is still down, so by
                // the time it lifts this guard is what stops the tap from also firing.
                onTap: { if !model.isEditing { model.activate(tile) } },
                onRemove: { model.removeTile(id: tile.id) }
            )

            // Dragging is an edit-mode gesture only. Outside it, the keycap's own press
            // gesture owns the touch and nothing competes for it.
            if model.isEditing {
                keycap
                    .draggable(tile.id.uuidString) {
                        // The preview is the cap itself, so what moves is what was grabbed.
                        KeycapView(tile: tile, activity: .idle, isDragging: true)
                            .frame(width: 150, height: 112)
                    }
                    .dropDestination(for: String.self) { items, _ in
                        move(items, to: DeckSlot(pageIndex: pageIndex, slotIndex: slot))
                    }
            } else {
                keycap.simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                        model.toggleEditing()
                    }
                )
            }
        } else {
            EmptySlotView { openAddTile(page: pageIndex) }
                .dropDestination(for: String.self) { items, _ in
                    move(items, to: DeckSlot(pageIndex: pageIndex, slotIndex: slot))
                }
        }
    }

    private func move(_ items: [String], to slot: DeckSlot) -> Bool {
        guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
        model.moveTile(id: id, to: slot)
        return true
    }

    private func openAddTile(page: Int) {
        model.setPage(page)
        isAddingTile = true
    }

    private var pageBinding: Binding<Int> {
        Binding(
            get: { model.currentPage },
            set: { model.setPage($0) }
        )
    }
}
