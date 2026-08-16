import DeckKit
import SwiftUI

/// S6 — add a tile: apps, Shortcuts, or a website.
///
/// Portrait layout: preview bar at the top, picker grid below, floating Add button.
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
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                previewBar
                Divider().overlay(DeckColor.strokeSubtle)
                pickerContent
            }

            // Floating Add button
            Button(action: add) {
                Text("Add")
                    .deckFont(.body)
                    .foregroundStyle(DeckColor.onMint)
                    .padding(.horizontal, DeckSpace.xl)
                    .frame(height: 48)
                    .background(DeckColor.mint, in: Capsule())
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .opacity(canAdd ? 1 : 0.4)
            .disabled(!canAdd)
            .padding(.trailing, DeckSpace.l)
            .padding(.bottom, DeckSpace.l)
        }
        .background(DeckColor.chassis)
        .preferredColorScheme(.dark)
        .task {
            model.requestCatalog()
            model.requestAllIcons()
        }
    }

    // MARK: - Top: preview bar

    private var previewBar: some View {
        HStack(spacing: DeckSpace.m) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DeckColor.inkMuted)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            KeycapView(
                tile: previewTile,
                activity: .idle,
                icon: tab == .app ? model.icons.image(forHash: selectedApp?.iconHash) : nil
            )
            .frame(width: 56, height: 56)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Label", text: $label)
                    .textFieldStyle(.plain)
                    .deckFont(.body)
                    .foregroundStyle(DeckColor.ink)

                if let slot = model.nextSlot {
                    Text(slot.humanReadable)
                        .deckFont(.meta)
                        .foregroundStyle(DeckColor.inkMuted)
                } else {
                    Text("All pages full")
                        .deckFont(.meta)
                        .foregroundStyle(DeckColor.ochre)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DeckSpace.m)
        .padding(.vertical, DeckSpace.s)
        .background(DeckColor.surfaceRaised)
    }

    // MARK: - Picker content

    private var pickerContent: some View {
        VStack(spacing: DeckSpace.m) {
            segmentedControl

            switch tab {
            case .app:
                searchField(placeholder: "Search apps on your Mac")
                appGrid
            case .shortcut:
                shortcutTab
            case .website:
                websiteTab
            }
        }
        .padding(.horizontal, DeckSpace.m)
        .padding(.top, DeckSpace.m)
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

    // MARK: - Apps: 3-column icon grid

    private let appColumns = Array(repeating: GridItem(.flexible(), spacing: DeckSpace.s), count: 3)

    @ViewBuilder
    private var appGrid: some View {
        let entries = model.searchResults(for: query)

        if entries.isEmpty {
            emptyState(
                model.catalog.isEmpty
                    ? "Waiting for your Mac's app list…"
                    : "No apps match \"\(query)\""
            )
        } else {
            ScrollView {
                LazyVGrid(columns: appColumns, spacing: DeckSpace.s) {
                    ForEach(entries, id: \.bundleID) { entry in
                        appCell(entry)
                    }
                }
                .padding(.bottom, 72) // space for floating button
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func appCell(_ entry: AppCatalogEntry) -> some View {
        let isSelected = selectedApp?.bundleID == entry.bundleID
        let icon = model.icons.image(forHash: entry.iconHash)

        return Button {
            selectedApp = entry
            label = entry.name
        } label: {
            VStack(spacing: 4) {
                if let icon {
                    icon.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    // Fallback: first letter of app name
                    Text(String(entry.name.prefix(1)).uppercased())
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(DeckColor.ink)
                        .frame(width: 48, height: 48)
                        .background(Color(hex: 0x2C2C2C), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Text(entry.name)
                    .deckFont(.meta)
                    .foregroundStyle(DeckColor.inkMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DeckSpace.s)
            .background(
                isSelected ? DeckColor.mint.opacity(0.12) : .clear,
                in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                    .strokeBorder(isSelected ? DeckColor.mint : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shortcuts

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

            searchField(placeholder: "Search Shortcuts")
            if names.isEmpty {
                emptyState("No Shortcuts match \"\(query)\"")
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(names, id: \.self) { name in
                            shortcutRow(name)
                        }
                    }
                    .padding(.bottom, 72)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func shortcutRow(_ name: String) -> some View {
        let isSelected = selectedShortcut == name
        return Button {
            selectedShortcut = name
            label = name
        } label: {
            HStack(spacing: DeckSpace.m) {
                RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous)
                    .fill(Color(hex: 0x2C2C2C))
                    .frame(width: 26, height: 26)
                Text(name)
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

    // MARK: - Website

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

            if !isURLValid && !urlText.isEmpty {
                Text("Needs a valid http(s) address")
                    .deckFont(.bodySmall)
                    .foregroundStyle(DeckColor.redInk)
            }

            emojiPicker
            Spacer(minLength: 0)
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
                    emoji = String(new.prefix(1))
                }
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

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .deckFont(.bodySmall)
            .foregroundStyle(DeckColor.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DeckSpace.l)
    }
}
