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
    @State private var showRecents = false
    @State private var selectedTab = 0 // 0 = Deck, 1 = Settings, 2 = triggers recents
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Always 4×2 landscape layout in portrait frame

    /// The deck grid rotated to landscape inside the portrait tab.
    private var deckContent: some View {
        GeometryReader { geo in
            let portraitW = geo.size.width
            let portraitH = geo.size.height
            let landscapeW = portraitH
            let landscapeH = portraitW

            HStack(spacing: 6) {
                // Mic button — LEFT in landscape = phone BOTTOM after -90° rotation
                // Half the height of an app icon
                GeometryReader { cellGeo in
                    let iconSize = min(cellGeo.size.width, cellGeo.size.height / 2) * 0.8
                    VStack {
                        Spacer()
                        Button {
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
                                .font(.system(size: 24))
                                .foregroundStyle(voiceRecognizer.isRecording ? DeckColor.red : DeckColor.inkMuted)
                                .frame(width: iconSize * 0.5, height: iconSize * 0.5)
                                .background(
                                    voiceRecognizer.isRecording ? DeckColor.redBackground : Color.white.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .frame(width: 44)

                // Grid + recents + page dots
                VStack(spacing: 4) {
                    pages
                        .frame(maxWidth: .infinity)
                    .opacity(model.session.state.deckOpacity)
                    .disabled(!model.session.acceptsActions && !model.isEditing)
                    .animation(reduceMotion ? nil : DeckMotion.stateChange, value: model.session.state)

                    Spacer(minLength: 0)

                    bottomBar
                }
            }
            .padding(.vertical, DeckSpace.s)
            .padding(.leading, DeckSpace.xs)
            .padding(.trailing, DeckSpace.l)
            .frame(width: landscapeW, height: landscapeH)
            .background(DeckColor.chassis)
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
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        // Swipe down in landscape → show emoji
                        if value.translation.height > 50 && abs(value.translation.height) > abs(value.translation.width) {
                            showEmojiOverlay = true
                        }
                    }
            )
            .rotationEffect(.degrees(-90))
            .frame(width: portraitW, height: portraitH)
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Group {
                if showRecents {
                    recentsPage
                        .background(DeckColor.chassis.ignoresSafeArea())
                } else {
                    deckContent
                        .background(DeckColor.chassis.ignoresSafeArea())
                }
            }
            .tabItem {
                Image(systemName: showRecents ? "clock.arrow.circlepath" : "square.grid.2x2")
                Text(showRecents ? "History" : "Deck")
            }
            .tag(0)

            SettingsView(model: model)
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .tag(1)

            // History tab — tapping toggles recents view
            Color.clear
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("History")
                }
                .tag(2)
        }
        .tint(DeckColor.mint)
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 2 {
                showRecents.toggle()
                selectedTab = 0
            } else if newValue == 1 {
                showRecents = false
            }
        }
        .background {
            WindowGestureInstaller(onAction: { model.sendGesture($0) })
        }
        .sheet(isPresented: $isAddingTile) {
            AddTileView(model: model)
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
                    onActivate: { bundleID, windowID in
                        model.activateSession(bundleID: bundleID, windowID: windowID)
                    }
                )
                .tag(aiPageTag)
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


    /// App Time Travel — stacked recent apps, most recent on right (= phone top).
    private var recentsPage: some View {
        GeometryReader { geo in
            let portraitW = geo.size.width
            let portraitH = geo.size.height
            let landscapeW = portraitH
            let landscapeH = portraitW
            let iconSize = landscapeH * 0.55

            HStack(spacing: -iconSize * 0.35) {
                // Oldest first (left/bottom), most recent last (right/top)
                ForEach(Array(model.macState.recents.reversed().enumerated()), id: \.element) { index, bundleID in
                    let total = model.macState.recents.count
                    let isMostRecent = index == total - 1

                    Button {
                        model.activateRecent(bundleID)
                    } label: {
                        Group {
                            if let icon = model.icon(forBundleID: bundleID) {
                                icon.resizable().aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous))
                            } else {
                                let name = model.name(forBundleID: bundleID)
                                Text(String(name.prefix(1)).uppercased())
                                    .font(.system(size: iconSize * 0.3, weight: .bold))
                                    .foregroundStyle(DeckColor.ink)
                                    .frame(width: iconSize, height: iconSize)
                                    .background(Color(hex: 0x2A2A2A))
                                    .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous))
                            }
                        }
                        .frame(width: isMostRecent ? iconSize * 1.1 : iconSize,
                               height: isMostRecent ? iconSize * 1.1 : iconSize)
                        .padding(1.5)
                        .background(Color.white.opacity(isMostRecent ? 0.1 : 0.05))
                        .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.22 + 1.5, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: iconSize * 0.22 + 1.5, style: .continuous)
                                .strokeBorder(Color.white.opacity(isMostRecent ? 0.15 : 0.08), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
                    }
                    .buttonStyle(TileButtonStyle())
                    .zIndex(Double(index)) // Most recent on top of stack
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(width: landscapeW, height: landscapeH)
            .rotationEffect(.degrees(-90))
            .frame(width: portraitW, height: portraitH)
        }
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
