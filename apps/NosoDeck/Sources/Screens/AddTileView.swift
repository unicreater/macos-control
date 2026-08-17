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
    @State private var selectedApps: Set<String> = [] // bundleIDs
    @State private var selectedShortcut: String?
    @State private var urlText = ""
    @State private var label = ""
    @State private var emoji = "⚡️"
    @State private var hasAcceptedAutomationPrompt = false
    @State private var disabledBrowsers: Set<String> = []
    @State private var sortByRecent = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                previewBar
                Divider().overlay(DeckColor.strokeSubtle)
                pickerContent
            }

            // Floating Add button
            Button(action: add) {
                Text(tab == .app && selectedApps.count > 1 ? "Add \(selectedApps.count)" : "Add")
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
                icon: tab == .app ? model.icons.image(forHash: selectedAppEntry?.iconHash) : nil
            )
            .frame(width: 56, height: 56)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 2) {
                if tab == .app && selectedApps.count > 1 {
                    Text("\(selectedApps.count) apps selected")
                        .deckFont(.body)
                        .foregroundStyle(DeckColor.ink)
                } else {
                    TextField("Label", text: $label)
                        .textFieldStyle(.plain)
                        .deckFont(.body)
                        .foregroundStyle(DeckColor.ink)
                }

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
                HStack {
                    searchField(placeholder: "Search apps on your Mac")
                    sortToggle
                }
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

    private var sortToggle: some View {
        Button {
            sortByRecent.toggle()
        } label: {
            Image(systemName: sortByRecent ? "clock" : "textformat.abc")
                .font(.system(size: 16))
                .foregroundStyle(DeckColor.inkMuted)
                .frame(width: 38, height: 38)
                .background(DeckColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                        .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func sortedEntries(_ entries: [AppCatalogEntry]) -> [AppCatalogEntry] {
        guard sortByRecent else { return entries }
        let recents = model.macState.recents
        return entries.sorted { lhs, rhs in
            let lhsIdx = recents.firstIndex(of: lhs.bundleID)
            let rhsIdx = recents.firstIndex(of: rhs.bundleID)
            switch (lhsIdx, rhsIdx) {
            case (.some(let l), .some(let r)): return l > r // more recent = later in array
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private let appColumns = Array(repeating: GridItem(.flexible(), spacing: DeckSpace.s), count: 3)

    @ViewBuilder
    private var appGrid: some View {
        let entries = sortedEntries(model.searchResults(for: query))

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
        let isSelected = selectedApps.contains(entry.bundleID)
        let icon = model.icons.image(forHash: entry.iconHash)

        return Button {
            if selectedApps.contains(entry.bundleID) {
                selectedApps.remove(entry.bundleID)
            } else {
                selectedApps.insert(entry.bundleID)
            }
            if selectedApps.count == 1 {
                label = selectedAppEntry?.name ?? entry.name
            }
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

    /// Browsers present in the current tab list, in stable order.
    private var activeBrowsers: [String] {
        var seen: Set<String> = []
        return model.browserTabs.compactMap { tab in
            guard !tab.browser.isEmpty else { return nil }
            return seen.insert(tab.browser).inserted ? tab.browser : nil
        }
    }

    /// Tabs filtered by enabled browsers.
    private var visibleTabs: [BrowserTab] {
        model.browserTabs.filter { !disabledBrowsers.contains($0.browser) }
    }

    private var websiteTab: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: browser sidebar
            if !model.browserTabs.isEmpty {
                browserSidebar
            }

            // Right: tabs list or loader
            if model.browserTabs.isEmpty {
                VStack(spacing: DeckSpace.m) {
                    Spacer()
                    ProgressView()
                        .tint(DeckColor.inkMuted)
                    Text("Loading tabs from your Mac…")
                        .deckFont(.bodySmall)
                        .foregroundStyle(DeckColor.inkMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if visibleTabs.isEmpty {
                emptyState("All browsers hidden — tap one to show its tabs")
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(visibleTabs, id: \.url) { tab in
                            browserTabRow(tab)
                        }
                    }
                    .padding(.bottom, 72)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    /// The bundleID for the first tab of a given browser name.
    private func bundleID(for browser: String) -> String? {
        model.browserTabs.first { $0.browser == browser }?.browserBundleID
    }

    /// Real app icon for a browser, falling back to SF Symbol.
    @ViewBuilder
    private func browserIconView(_ bundleID: String?, size: CGFloat) -> some View {
        if let bundleID, let icon = model.icon(forBundleID: bundleID) {
            icon.resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            Image(systemName: "globe")
                .font(.system(size: size * 0.5))
                .foregroundStyle(DeckColor.inkMuted)
                .frame(width: size, height: size)
        }
    }

    /// Left sidebar: vertical strip of browser icons. Tap to toggle that browser's tabs.
    private var browserSidebar: some View {
        VStack(spacing: DeckSpace.s) {
            ForEach(activeBrowsers, id: \.self) { browser in
                let isEnabled = !disabledBrowsers.contains(browser)
                let bid = bundleID(for: browser)
                Button {
                    if isEnabled {
                        disabledBrowsers.insert(browser)
                    } else {
                        disabledBrowsers.remove(browser)
                    }
                } label: {
                    browserIconView(bid, size: 32)
                        .frame(width: 44, height: 44)
                        .background(
                            isEnabled ? DeckColor.surfaceRaised : .clear,
                            in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                                .strokeBorder(isEnabled ? DeckColor.mint : Color(hex: 0x2C2C2C), lineWidth: 1)
                        }
                        .opacity(isEnabled ? 1 : 0.4)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, DeckSpace.s)
    }

    private func browserTabRow(_ tab: BrowserTab) -> some View {
        let isSelected = urlText == tab.url
        return Button {
            urlText = tab.url
            if label.isEmpty || label == "Tile" {
                label = tab.title
            }
        } label: {
            HStack(spacing: DeckSpace.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title)
                        .deckFont(.body)
                        .foregroundStyle(DeckColor.ink)
                        .lineLimit(1)
                    Text(tab.url)
                        .deckFont(.meta)
                        .foregroundStyle(DeckColor.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: DeckSpace.xs)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12))
                        .foregroundStyle(DeckColor.mint)
                }
                browserIconView(tab.browserBundleID.isEmpty ? nil : tab.browserBundleID, size: 20)
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
        if kind == .website {
            model.requestBrowserTabs()
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

    /// First selected app entry (for preview icon and single-select label).
    private var selectedAppEntry: AppCatalogEntry? {
        guard let first = selectedApps.first else { return nil }
        return model.catalog.first { $0.bundleID == first }
    }

    private var target: TileTarget? {
        switch tab {
        case .app:
            return selectedAppEntry.map { .app(bundleID: $0.bundleID) }
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
        switch tab {
        case .app:
            return !selectedApps.isEmpty && model.nextSlot != nil
        case .shortcut:
            return selectedShortcut != nil
                && model.nextSlot != nil
                && !label.trimmingCharacters(in: .whitespaces).isEmpty
        case .website:
            return isURLValid
                && model.nextSlot != nil
                && !label.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func add() {
        switch tab {
        case .app:
            for bundleID in selectedApps {
                guard let entry = model.catalog.first(where: { $0.bundleID == bundleID }) else { continue }
                model.add(Tile(target: .app(bundleID: bundleID), label: entry.name))
            }
        case .shortcut:
            guard let target else { return }
            model.add(Tile(target: target, label: label.trimmingCharacters(in: .whitespaces), emoji: emoji))
        case .website:
            guard let target else { return }
            model.add(Tile(target: target, label: label.trimmingCharacters(in: .whitespaces), emoji: emoji))
        }
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
