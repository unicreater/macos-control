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

            VStack(spacing: 4) {
                    pages
                        .frame(maxWidth: .infinity)
                    .opacity(model.session.state.deckOpacity)
                    .disabled(!model.session.acceptsActions && !model.isEditing)
                    .animation(reduceMotion ? nil : DeckMotion.stateChange, value: model.session.state)

                    Spacer(minLength: 0)

                    bottomBar
                }
            .padding(.vertical, DeckSpace.s)
            .padding(.leading, DeckSpace.l) // Extra space on LEFT = phone BOTTOM (floating buttons)
            .padding(.trailing, DeckSpace.m)
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
        ZStack(alignment: .bottom) {
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
                    Image(systemName: "square.grid.2x2")
                    Text("Deck")
                }
                .tag(0)

                SettingsView(model: model)
                    .tabItem {
                        Image(systemName: "gearshape")
                        Text("Settings")
                    }
                    .tag(1)
            }
            .tint(DeckColor.mint)
            .onChange(of: selectedTab) { _, newValue in
                if newValue != 0 { showRecents = false }
            }

            // Floating buttons — bottom-trailing, above tab bar
            HStack(spacing: 12) {
                Spacer()

                // Mic button
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

                // History toggle
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if showRecents {
                        showRecents = false
                    } else {
                        showRecents = true
                        selectedTab = 0
                    }
                } label: {
                    Image(systemName: showRecents ? "square.grid.2x2" : "clock.arrow.circlepath")
                        .font(.system(size: 18))
                        .foregroundStyle(showRecents ? DeckColor.mint : DeckColor.inkMuted)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 58)
        }
        .background {
            WindowGestureInstaller(onAction: { model.sendGesture($0) })
        }
        .sheet(isPresented: $isAddingTile) {
            AddTileView(model: model)
                .rotationEffect(.degrees(-90))
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


    /// App Time Travel — scrollable stacked recent apps.
    private var recentsPage: some View {
        GeometryReader { geo in
            let portraitW = geo.size.width
            let portraitH = geo.size.height
            let landscapeW = portraitH
            let landscapeH = portraitW
            let baseSize = landscapeH * 0.38
            let focusedSize = baseSize * 1.15

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -baseSize * 0.25) {
                    let recents = model.macState.recents.reversed() as [String]
                    let total = recents.count
                    let midIndex = total / 2

                    ForEach(Array(recents.enumerated()), id: \.element) { index, bundleID in
                        let isFocused = index == midIndex
                        let size = isFocused ? focusedSize : baseSize
                        let radius = size * 0.22

                        recentTile(bundleID: bundleID, size: size, isFocused: isFocused)
                            .zIndex(Double(index))
                    }
                }
                .padding(.horizontal, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(width: landscapeW, height: landscapeH)
            .rotationEffect(.degrees(-90))
            .frame(width: portraitW, height: portraitH)
        }
    }

    private func recentTile(bundleID: String, size: CGFloat, isFocused: Bool) -> some View {
        let radius = size * 0.22
        return Button {
            model.activateRecent(bundleID)
        } label: {
            recentIcon(bundleID: bundleID, size: size, radius: radius)
                .padding(1.5)
                .background(Color.white.opacity(isFocused ? 0.12 : 0.05))
                .clipShape(RoundedRectangle(cornerRadius: radius + 1.5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius + 1.5, style: .continuous)
                        .strokeBorder(Color.white.opacity(isFocused ? 0.15 : 0.1), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        }
        .buttonStyle(TileButtonStyle())
    }

    @ViewBuilder
    private func recentIcon(bundleID: String, size: CGFloat, radius: CGFloat) -> some View {
        if let icon = model.icon(forBundleID: bundleID) {
            icon.renderingMode(.original)
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            Text(String(model.name(forBundleID: bundleID).prefix(1)).uppercased())
                .font(.system(size: size * 0.3, weight: .bold))
                .foregroundStyle(DeckColor.ink)
                .frame(width: size, height: size)
                .background(Color(hex: 0x2A2A2A))
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
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
