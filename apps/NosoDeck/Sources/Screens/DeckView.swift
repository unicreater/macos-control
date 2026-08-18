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
    @StateObject private var voiceRecognizer = SpeechRecognizer()
    @State private var showEmojiOverlay = false
    @State private var showRadialMenu = false
    @State private var editingTile: Tile?
    @State var selectedTab = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Always 4×2 landscape layout in portrait frame

    /// The deck grid — landscape-rotated or portrait, based on setting.
    private var deckContent: some View {
        GeometryReader { geo in
            let portraitW = geo.size.width
            let portraitH = geo.size.height
            let isLandscape = model.isLandscapeLayout
            let contentW = isLandscape ? portraitH : portraitW
            let contentH = isLandscape ? portraitW : portraitH

            deckInner
                .padding(.vertical, DeckSpace.xl)
                .padding(.horizontal, isLandscape ? DeckSpace.m : DeckSpace.m)
                .padding(.leading, isLandscape ? DeckSpace.xxxl - DeckSpace.m : 0)
                .frame(width: contentW, height: contentH)
                .overlay {
                    VoiceOverlay(recognizer: voiceRecognizer) {
                        let text = voiceRecognizer.sendableText
                        if !text.isEmpty { model.sendVoiceText(text) }
                        voiceRecognizer.clear()
                    }
                    .animation(.easeInOut(duration: 0.2), value: voiceRecognizer.isRecording)
                }
                .overlay {
                    if showEmojiOverlay {
                        ZStack {
                            Color.black.opacity(0.7)
                                .onTapGesture { showEmojiOverlay = false }
                            VStack(spacing: 16) {
                                EmojiStrip(isEnabled: model.session.acceptsActions) { emoji in
                                    model.send(emoji: emoji)
                                    showEmojiOverlay = false
                                }
                                Text("Tap emoji to send, or tap anywhere to close")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DeckColor.inkFaint)
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showEmojiOverlay)
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if voiceRecognizer.isRecording {
                            voiceRecognizer.stop()
                            let text = voiceRecognizer.sendableText
                            if !text.isEmpty { model.sendVoiceText(text) }
                            voiceRecognizer.clear()
                        } else {
                            voiceRecognizer.start()
                        }
                    } label: {
                        Image(systemName: voiceRecognizer.isRecording ? "stop.circle.fill" : "mic.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(voiceRecognizer.isRecording ? DeckColor.red : DeckColor.inkMuted)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
                }
                .if(isLandscape) { view in
                    view
                        .rotationEffect(.degrees(-90))
                        .frame(width: portraitW, height: portraitH)
                }
        }
    }

    private var deckInner: some View {
        VStack(spacing: 4) {
            pages
                .frame(maxWidth: .infinity)
                .disabled(!model.session.acceptsActions && !model.isEditing)
                .animation(reduceMotion ? nil : DeckMotion.stateChange, value: model.session.state)

            Spacer(minLength: 0)

            bottomBar
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                Tab("Deck", systemImage: "square.grid.2x2", value: 0) {
                    deckContent
                        .themeBackground()
                        .overlay {
                            if showRadialMenu {
                                RadialMenuView(
                                    frontmostBundleID: model.macState.frontmost,
                                    isLandscape: model.isLandscapeLayout,
                                    onAction: { action in
                                        model.sendGesture(action)
                                    },
                                    onDismiss: { showRadialMenu = false }
                                )
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.15), value: showRadialMenu)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if model.lastRemovedTile != nil {
                                undoToast
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                    .padding(.bottom, 80)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: model.lastRemovedTile != nil)
                }

                Tab("Settings", systemImage: "gearshape", value: 1) {
                    SettingsView(model: model)
                        .themeBackground()
                }

                Tab("History", systemImage: "clock.arrow.circlepath", value: 2, role: .search) {
                    HistoryView(model: model)
                        .toolbarBackground(.hidden, for: .tabBar)
                        .scrollContentBackground(.hidden)
                }
            }
            .tint(DeckColor.mint)
        }
        .background {
            WindowGestureInstaller(onAction: { model.sendGesture($0) }, mapping: model.gestureMapping)
        }
        .sheet(isPresented: $isAddingTile) {
            AddTileView(model: model)
        }
        .sheet(item: $editingTile) { tile in
            EditTileSheet(tile: tile) { newLabel, newEmoji in
                model.updateTile(id: tile.id, label: newLabel, emoji: newEmoji)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: paywallBinding) {
            PaywallView(store: model.entitlements, reason: model.paywallReason)
        }
        .task { await model.entitlements.start() }
        .onAppear {
            voiceRecognizer.warmUp()
            SpeechRecognizer.bulletStyle = model.bulletStyle
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

            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if model.isEditing {
            editPageStrip
        } else {
            HStack(spacing: 8) {
                Spacer()
                ForEach(0..<model.pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == model.currentPage ? DeckColor.ink : Color(hex: 0x333333))
                        .frame(width: 7, height: 7)
                        .onTapGesture { model.setPage(index) }
                }
                if hasAISessions {
                    Circle()
                        .fill(model.currentPage == aiPageTag ? DeckColor.mint : DeckColor.mint.opacity(0.3))
                        .frame(width: 7, height: 7)
                        .onTapGesture { model.setPage(aiPageTag) }
                }
                Spacer()
            }
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

            Button { model.toggleEditing() } label: {
                Text("Done")
                    .deckFont(.legend)
                    .foregroundStyle(DeckColor.onMint)
                    .padding(.horizontal, DeckSpace.l)
                    .frame(height: 32)
                    .background(DeckColor.mint, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
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

    private var isDeckEmpty: Bool {
        model.deck.pages.allSatisfy { $0.isEmpty }
    }

    private var pages: some View {
        TabView(selection: pageBinding) {
            ForEach(0..<model.pageCount, id: \.self) { pageIndex in
                VStack {
                    if isDeckEmpty && pageIndex == 0 {
                        emptyDeckOnboarding
                    } else {
                        grid(pageIndex: pageIndex)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.95).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    Spacer(minLength: 0)
                }
                .tag(pageIndex)
            }
            if hasAISessions {
                AISessionsView(
                    sessions: model.macState.sessions,
                    iconProvider: { model.icon(forBundleID: $0) },
                    onActivate: { bundleID, windowID in
                        model.activateSession(bundleID: bundleID, windowID: windowID)
                    },
                    isPortrait: !model.isLandscapeLayout
                )
                .tag(aiPageTag)
            }
        }   
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var gridRows: Int {
        model.isLandscapeLayout ? DeckGrid.rows : DeckGrid.rows(isPortrait: true)
    }

    private var gridColumns: Int {
        model.isLandscapeLayout ? DeckGrid.columns : DeckGrid.columns(isPortrait: true)
    }

    private func grid(pageIndex: Int) -> some View {
        let page = model.deck.pages[pageIndex]

        return VStack(spacing: DeckGrid.gutter) {
            ForEach(0..<gridRows, id: \.self) { row in
                HStack(spacing: DeckGrid.gutter) {
                    ForEach(0..<gridColumns, id: \.self) { column in
                        let slot = row * gridColumns + column
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
            let shortcutName: String? = { if case .shortcut(let name) = tile.target { return name } else { return nil } }()
            let keycap = KeycapView(
                tile: tile,
                activity: model.activity(for: tile),
                isEditing: model.isEditing,
                editIndex: slot,
                icon: model.icon(for: tile),
                shortcutColor: shortcutName.flatMap { model.shortcutColor(for: $0) },
                // A long press flips edit mode while the finger is still down, so by
                // the time it lifts this guard is what stops the tap from also firing.
                onTap: {
                    if model.isEditing {
                        editingTile = tile
                    } else if model.activity(for: tile) == .frontmost {
                        showRadialMenu = true
                    } else {
                        model.activate(tile)
                    }
                },
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

    private var emptyDeckOnboarding: some View {
        VStack(spacing: DeckSpace.l) {
            Spacer()

            Image(systemName: "square.grid.2x2")
                .font(.system(size: 44))
                .foregroundStyle(DeckColor.inkFaint)

            Text("Your deck is empty")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(DeckColor.ink)

            Text("Add apps, shortcuts, websites,\nor keyboard combos to get started.")
                .deckFont(.bodySmall)
                .foregroundStyle(DeckColor.inkMuted)
                .multilineTextAlignment(.center)

            Button {
                isAddingTile = true
            } label: {
                Text("Add your first tile")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DeckColor.chassis)
                    .padding(.horizontal, DeckSpace.xl)
                    .frame(height: 48)
                    .background(DeckColor.mint, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func openAddTile(page: Int) {
        model.setPage(page)
        isAddingTile = true
    }

    private var undoToast: some View {
        HStack(spacing: DeckSpace.m) {
            Text("Tile removed")
                .deckFont(.body)
                .foregroundStyle(DeckColor.ink)
            Spacer()
            Button {
                model.undoRemoveTile()
            } label: {
                Text("Undo")
                    .deckFont(.legend)
                    .foregroundStyle(DeckColor.mint)
                    .padding(.horizontal, DeckSpace.m)
                    .frame(height: 32)
                    .background(DeckColor.mint.opacity(0.15), in: RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DeckSpace.l)
        .padding(.vertical, DeckSpace.s)
        .background(DeckColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
                .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        .padding(.horizontal, DeckSpace.xl)
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
            set: { newPage in
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                    model.setPage(newPage)
                }
            }
        )
    }

    private func landscapeRotated<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { geo in
            let portraitW = geo.size.width
            let portraitH = geo.size.height
            let landscapeW = portraitH
            let landscapeH = portraitW

            content()
                .frame(width: landscapeW, height: landscapeH)
                .background(DeckColor.chassis.ignoresSafeArea())
                .rotationEffect(.degrees(-90))
                .frame(width: portraitW, height: portraitH)
        }
    }

}

private extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}

#if DEBUG
#Preview("Deck Grid") {
    let model = AppModel.preview(tiles: [
        Tile(target: .app(bundleID: "com.apple.Safari"), label: "Safari", emoji: "🧭"),
        Tile(target: .app(bundleID: "com.apple.Music"), label: "Music", emoji: "🎵"),
        Tile(target: .app(bundleID: "com.apple.Notes"), label: "Notes", emoji: "📝"),
        Tile(target: .shortcut(name: "Focus"), label: "Focus", emoji: "🎯"),
        Tile(target: .app(bundleID: "com.apple.Xcode"), label: "Xcode", emoji: "🔨"),
    ])
    DeckView(model: model)
        .preferredColorScheme(.dark)
}

#endif
