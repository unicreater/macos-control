import DeckKit
import SwiftUI

/// S4 and S5 — the deck itself, and its edit mode.
///
/// One gesture per region, as the handoff insists: tap a tile to activate, horizontal
/// swipe to change page, long-press to edit. Nothing competes on the same surface.
struct DeckView: View {
    let model: AppModel

    @State private var isConfirmingUnpair = false
    @State private var isConfirmingPageDelete = false
    @State private var isAddingTile = false
    @State private var gestureFeedback: (String, String)? // (label, icon)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isPortrait: Bool { verticalSizeClass == .regular }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.bottom, 14)

            HStack(spacing: DeckGrid.recentsColumnGap) {
                // Recents column only in landscape — no room in portrait.
                if !isPortrait {
                    RecentsColumn(
                        bundleIDs: model.visibleRecents,
                        isUnlocked: model.entitlement.unlocksRecentsColumn,
                        iconProvider: { model.icon(forBundleID: $0) },
                        nameProvider: { model.name(forBundleID: $0) },
                        onActivate: { model.activateRecent($0) },
                        onUpgrade: { model.presentPaywall(reason: "The recents column is part of Premium.") }
                    )
                }

                pages
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        .background {
            // Multi-finger gesture detection layer — in background with hit testing
            // disabled so all single-finger taps reach the tiles. The UIKit gesture
            // recognizers still fire because they're attached at the window level.
            GestureOverlay(
                onAction: { model.sendGesture($0) },
                onFeedback: { label, icon in
                    withAnimation(.easeOut(duration: 0.15)) {
                        gestureFeedback = (label, icon)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            gestureFeedback = nil
                        }
                    }
                }
            )
            .allowsHitTesting(false)
        }
        .overlay {
            // Gesture feedback badge
            if let feedback = gestureFeedback {
                HStack(spacing: 8) {
                    Image(systemName: feedback.1)
                        .font(.system(size: 20, weight: .medium))
                    Text(feedback.0.uppercased())
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(DeckColor.mint)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(DeckColor.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(DeckColor.mint.opacity(0.3), lineWidth: 1) }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .sheet(isPresented: $isAddingTile) {
            AddTileView(model: model)
        }
        .sheet(isPresented: paywallBinding) {
            PaywallView(store: model.entitlements, reason: model.paywallReason)
        }
        .task { await model.entitlements.start() }
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
                        .frame(height: 44)
                        .background(DeckColor.mint, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
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

                if model.isEmojiStripEnabled {
                    EmojiStrip(isEnabled: model.session.acceptsActions) { emoji in
                        model.send(emoji: emoji)
                    }
                }

                Button { model.openSettings() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .foregroundStyle(DeckColor.inkMuted)
                        .frame(width: 44, height: 44)
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

    @ViewBuilder
    private var bottomBar: some View {
        if model.isEditing {
            editPageStrip
        } else {
            HStack(spacing: DeckSpace.s) {
                Spacer()
                // AI Sessions pip
                if hasAISessions {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                        Text("AI")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(model.currentPage == aiPageTag ? DeckColor.mint : DeckColor.inkMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        model.currentPage == aiPageTag ? DeckColor.mint.opacity(0.15) : Color(hex: 0x222222),
                        in: Capsule()
                    )
                    .onTapGesture { model.setPage(aiPageTag) }
                }
                ForEach(0..<model.pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == model.currentPage ? DeckColor.ink : Color(hex: 0x333333))
                        .frame(width: 22, height: 5)
                        .onTapGesture { model.setPage(index) }
                }
                if !model.canAddPage {
                    addPagePill
                }
                Spacer()
            }
            .accessibilityLabel("Page \(model.currentPage + 1) of \(model.pageCount)")
        }
    }

    /// S5's page strip: switch pages, add one, delete one with a confirm.
    private var editPageStrip: some View {
        HStack(spacing: DeckSpace.s) {
            ForEach(0..<model.pageCount, id: \.self) { index in
                Button { model.setPage(index) } label: {
                    Text("Page \(index + 1)")
                        .deckFont(.legend)
                        .foregroundStyle(index == model.currentPage ? DeckColor.mint : DeckColor.inkMuted)
                        .padding(.horizontal, DeckSpace.m)
                        .frame(height: 32)
                        .overlay {
                            RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous)
                                .strokeBorder(
                                    index == model.currentPage ? DeckColor.mint : Color(hex: 0x2C2C2C),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
            }

            addPagePill

            Spacer()

            if model.pageCount > 1 {
                Button { isConfirmingPageDelete = true } label: {
                    Text("Delete page")
                        .deckFont(.legend)
                        .foregroundStyle(DeckColor.redInk)
                }
                .buttonStyle(.plain)
            }
        }
        .confirmationDialog(
            "Delete page \(model.currentPage + 1)?",
            isPresented: $isConfirmingPageDelete,
            titleVisibility: .visible
        ) {
            Button("Delete page", role: .destructive) { model.removePage(at: model.currentPage) }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The tiles on this page are removed too. Your other pages are untouched.")
        }
    }

    private var addPagePill: some View {
        Button { model.addPage() } label: {
            Text("+ Page")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.onOchre)
                .padding(.horizontal, DeckSpace.m)
                .frame(height: model.isEditing ? 32 : 20)
                .background(DeckColor.ochre, in: RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.canAddPage ? "Add a page" : "Add a page — requires Premium")
    }

    // MARK: - Grid

    /// The total number of swipeable pages: deck pages + AI Sessions page (if any sessions exist).
    private var hasAISessions: Bool {
        !model.macState.sessions.isEmpty
    }

    /// Tag used for the AI Sessions page — sits after all deck pages.
    private var aiPageTag: Int { model.pageCount }

    private var pages: some View {
        TabView(selection: pageBinding) {
            ForEach(0..<model.pageCount, id: \.self) { pageIndex in
                grid(pageIndex: pageIndex)
                    .tag(pageIndex)
            }
            if hasAISessions {
                AISessionsView(
                    sessions: model.macState.sessions,
                    iconProvider: { model.icon(forBundleID: $0) },
                    onActivate: { bundleID in model.activateByBundleID(bundleID) }
                )
                .tag(aiPageTag)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func grid(pageIndex: Int) -> some View {
        let page = model.deck.pages[pageIndex]
        let cols = DeckGrid.columns(isPortrait: isPortrait)
        let rows = DeckGrid.rows(isPortrait: isPortrait)

        return VStack(spacing: DeckGrid.gutter) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: DeckGrid.gutter) {
                    ForEach(0..<cols, id: \.self) { column in
                        let slot = row * cols + column
                        cell(page: page, pageIndex: pageIndex, slot: slot)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(page: Page, pageIndex: Int, slot: Int) -> some View {
        if slot == page.tiles.count && pageIndex == 0 && !model.isEditing {
            // Voice tile sits in the first empty slot on page 1
            VoiceTile(isEnabled: model.session.acceptsActions) { text in
                model.sendVoiceText(text)
            }
        } else if slot < page.tiles.count {
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
                onRemove: { model.removeTile(id: tile.id) },
                onQuit: { if !model.isEditing { model.quit(tile) } }
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

    private var paywallBinding: Binding<Bool> {
        Binding(
            get: { model.isShowingPaywall },
            set: { if !$0 { model.dismissPaywall() } }
        )
    }

    private var pageBinding: Binding<Int> {
        Binding(
            get: { model.currentPage },
            set: { model.setPage($0) }
        )
    }

}
