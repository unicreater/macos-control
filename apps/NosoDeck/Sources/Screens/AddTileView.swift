import DeckKit
import SwiftUI

/// S6 — add a tile: apps, Shortcuts, or a website.
///
/// Because a page holds only eight tiles, the picker has to say where the tile is going
/// and warn when that fills the page. The preview is a live keycap, so what you see is
/// literally the component that will land on the deck.
struct AddTileView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var tab: TileKind = .app
    @State private var query = ""
    @State private var selectedApp: AppCatalogEntry?
    @State private var selectedShortcut: String?
    @State private var urlText = ""
    @State private var label = ""
    @State private var emoji = "⚡️"
    @State private var hasAcceptedAutomationPrompt = false

    var body: some View {
        HStack(alignment: .top, spacing: DeckSpace.xl) {
            picker
                .frame(maxWidth: .infinity)
            preview
                .frame(width: 290)
        }
        .padding(DeckSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckColor.chassis)
        .preferredColorScheme(.dark)
        .task { model.requestCatalog() }
    }

    // MARK: - Left: the picker

    private var picker: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            segmentedControl

            switch tab {
            case .app:
                searchField(placeholder: "Search apps on your Mac")
                appResults
            case .shortcut:
                shortcutTab
            case .website:
                websiteTab
            }

            Spacer(minLength: 0)
        }
    }

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(TileKind.allCases, id: \.self) { kind in
                Button { select(tab: kind) } label: {
                    Text(title(for: kind))
                        .deckFont(.legend)
                        .foregroundStyle(tab == kind ? Color(hex: 0x111111) : DeckColor.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(
                            tab == kind ? DeckColor.ink : .clear,
                            in: RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(DeckColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
        }
    }

    private func searchField(placeholder: String) -> some View {
        TextField(placeholder, text: $query)
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
    }

    @ViewBuilder
    private var appResults: some View {
        let entries = model.searchResults(for: query)

        if entries.isEmpty {
            emptyState(
                model.catalog.isEmpty
                    ? "Waiting for your Mac's app list…"
                    : "No apps match “\(query)”"
            )
        } else {
            list(entries) { entry in
                row(
                    title: entry.name,
                    isSelected: selectedApp?.bundleID == entry.bundleID,
                    icon: model.icons.image(forHash: entry.iconHash)
                ) {
                    selectedApp = entry
                    label = entry.name
                }
            }
        }
    }

    /// The Automation pre-prompt sits in front of the list, because asking the Mac for
    /// its Shortcuts is what raises the system dialog (FR-24).
    @ViewBuilder
    private var shortcutTab: some View {
        if !hasAcceptedAutomationPrompt && model.shortcuts.isEmpty {
            PrePromptCard(kind: .automation, allowTitle: "Show my Shortcuts") {
                hasAcceptedAutomationPrompt = true
                model.requestShortcuts()
            }
        } else if model.automationWasRefused {
            emptyState(
                "NosoDeck can't see your Shortcuts. \(PermissionKind.automation.degradedPath ?? "") You can allow it in System Settings → Privacy & Security → Automation on the Mac."
            )
        } else if model.shortcuts.isEmpty {
            emptyState("Waiting for your Mac's Shortcuts…")
        } else {
            let names = query.isEmpty
                ? model.shortcuts
                : model.shortcuts.filter { $0.range(of: query, options: .caseInsensitive) != nil }

            VStack(alignment: .leading, spacing: DeckSpace.m) {
                searchField(placeholder: "Search Shortcuts")
                if names.isEmpty {
                    emptyState("No Shortcuts match “\(query)”")
                } else {
                    list(names) { name in
                        row(title: name, isSelected: selectedShortcut == name, icon: nil) {
                            selectedShortcut = name
                            label = name
                        }
                    }
                }
            }
        }
    }

    private var websiteTab: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            TextField("https://example.com", text: $urlText)
                .textFieldStyle(.plain)
                .deckFont(.body)
                .foregroundStyle(DeckColor.ink)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, DeckSpace.m)
                .frame(height: 38)
                .background(Color(hex: 0x141414), in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                        .strokeBorder(isURLValid ? DeckColor.strokeSubtle : DeckColor.red, lineWidth: isURLValid ? 1 : 2)
                }

            // Inline and in place: the field is marked, the reason is stated, and the
            // ADD button dims rather than disappearing.
            if !isURLValid && !urlText.isEmpty {
                Text("Needs a valid http(s) address")
                    .deckFont(.bodySmall)
                    .foregroundStyle(DeckColor.redInk)
            }

            emojiPicker
        }
    }

    private var emojiPicker: some View {
        VStack(alignment: .leading, spacing: DeckSpace.s) {
            Text("Tile emoji")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.inkMuted)
            TextField("⚡️", text: $emoji)
                .textFieldStyle(.plain)
                .font(.system(size: 28))
                .foregroundStyle(DeckColor.ink)
                .multilineTextAlignment(.center)
                .frame(width: 64, height: 48)
                .background(Color(hex: 0x141414), in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                        .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
                }
                .onChange(of: emoji) { _, new in
                    // One character, so the keycap's 34pt glyph slot always fits.
                    emoji = String(new.prefix(1))
                }
        }
    }

    // MARK: - Right: the preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: DeckSpace.l) {
            Text("Preview")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.inkMuted)

            KeycapView(
                tile: previewTile,
                activity: .idle,
                icon: tab == .app ? model.icons.image(forHash: selectedApp?.iconHash) : nil
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
            buttons
        }
        .padding(20)
        .background(DeckColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
                .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
        }
    }

    /// Where it lands, and whether that fills the page — eight is a hard ceiling, and
    /// running into it should never be a surprise.
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

    private var buttons: some View {
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
            // Visible but dimmed while unusable — never hidden.
            .opacity(canAdd ? 1 : 0.4)
            .disabled(!canAdd)
        }
    }

    // MARK: - Composition

    private func select(tab kind: TileKind) {
        tab = kind
        query = ""
        label = ""
        if kind == .shortcut && !model.shortcuts.isEmpty {
            hasAcceptedAutomationPrompt = true
        }
    }

    private func title(for kind: TileKind) -> String {
        switch kind {
        case .app: return "Apps"
        case .shortcut: return "Shortcuts"
        case .website: return "Website"
        }
    }

    private var isURLValid: Bool { TileTarget.isValidWebsiteURL(urlText) }

    private var target: TileTarget? {
        switch tab {
        case .app:
            return selectedApp.map { .app(bundleID: $0.bundleID) }
        case .shortcut:
            return selectedShortcut.map { .shortcut(name: $0) }
        case .website:
            return isURLValid ? .website(url: urlText.trimmingCharacters(in: .whitespaces)) : nil
        }
    }

    private var previewTile: Tile {
        Tile(
            target: target ?? .app(bundleID: ""),
            label: label.isEmpty ? "Tile" : label,
            // Only Shortcut and website tiles carry an emoji; app tiles show the real
            // icon the Mac sent.
            emoji: tab == .app ? nil : emoji
        )
    }

    private var canAdd: Bool {
        target != nil
            && model.nextSlot != nil
            && !label.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func add() {
        guard let target else { return }
        model.add(Tile(
            target: target,
            label: label.trimmingCharacters(in: .whitespaces),
            emoji: tab == .app ? nil : emoji
        ))
        dismiss()
    }

    // MARK: - Small shared pieces

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .deckFont(.bodySmall)
            .foregroundStyle(DeckColor.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DeckSpace.l)
    }

    private func list<Item: Hashable, RowContent: View>(
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> RowContent
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(items, id: \.self) { item in
                    row(item)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func row(
        title: String,
        isSelected: Bool,
        icon: Image?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DeckSpace.m) {
                if let icon {
                    icon.resizable().frame(width: 26, height: 26)
                } else {
                    RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous)
                        .fill(Color(hex: 0x2C2C2C))
                        .frame(width: 26, height: 26)
                }
                Text(title)
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
}
