import DeckKit
import SwiftUI

/// The tabs shown in the add-tile picker.
private enum AddTileTab: String, CaseIterable {
    case apps = "Apps"
    case shortcuts = "Shortcuts"
    case openTabs = "Open Tabs"
    case popular = "Popular"
    case keys = "Keys"
}

/// S6 — add a tile: apps, Shortcuts, or a website.
///
/// Portrait layout: preview bar at the top, picker grid below, floating Add button.
struct AddTileView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var tab: AddTileTab = .apps
    @State private var query = ""
    @State private var selectedApps: Set<String> = [] // bundleIDs
    @State private var selectedShortcut: String?
    @State private var urlText = ""
    @State private var label = ""
    @State private var emoji = "⚡️"
    @State private var hasAcceptedAutomationPrompt = false
    @State private var disabledBrowsers: Set<String> = []
    @State private var expandedFolders: Set<String> = []
    @State private var sortByRecent = false
    @State private var selectedKeyCombo: KeyComboPreset?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                previewBar
                Divider().overlay(DeckColor.strokeSubtle)
                pickerContent
            }

            // Floating Add button
            Button(action: add) {
                Text(tab == .apps && selectedApps.count > 1 ? "Add \(selectedApps.count)" : "Add")
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
                icon: tab == .apps ? model.icons.image(forHash: selectedAppEntry?.iconHash) : nil
            )
            .frame(width: 56, height: 56)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 2) {
                if tab == .apps && selectedApps.count > 1 {
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
            tabPills

            switch tab {
            case .apps:
                HStack {
                    searchField(placeholder: "Search apps on your Mac")
                    sortToggle
                }
                appGrid
            case .shortcuts:
                shortcutTab
            case .openTabs:
                websiteTab
            case .popular:
                popularSitesTab
            case .keys:
                keyComboTab
            }
        }
        .padding(.horizontal, DeckSpace.m)
        .padding(.top, DeckSpace.m)
    }

    private var tabPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DeckSpace.s) {
                ForEach(AddTileTab.allCases, id: \.self) { t in
                    Button { selectTab(t) } label: {
                        Text(t.rawValue)
                            .deckFont(.legend)
                            .foregroundStyle(tab == t ? Color(hex: 0x111111) : DeckColor.inkMuted)
                            .padding(.horizontal, DeckSpace.m)
                            .frame(height: 32)
                            .background(
                                tab == t ? DeckColor.ink : DeckColor.surfaceRaised,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule().strokeBorder(
                                    tab == t ? .clear : DeckColor.strokeSubtle,
                                    lineWidth: 1
                                )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
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
        if model.automationWasRefused {
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
        let info = model.shortcutInfos.first { $0.name == name }
        let color = info.map { Color(red: Double($0.colorR) / 255, green: Double($0.colorG) / 255, blue: Double($0.colorB) / 255) } ?? Color(hex: 0x2C2C2C)
        return Button {
            selectedShortcut = name
            label = name
        } label: {
            HStack(spacing: DeckSpace.m) {
                RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous)
                    .fill(color)
                    .frame(width: 26, height: 26)
                    .overlay {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.9))
                    }
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

    private struct TabGroup: Identifiable {
        let folder: String
        let tabs: [BrowserTab]
        var id: String { folder }
    }

    private var groupedTabs: [TabGroup] {
        var groups: [(String, [BrowserTab])] = []
        var seen: Set<String> = []
        for tab in visibleTabs {
            let folder = tab.folder ?? "Tabs"
            if !seen.contains(folder) {
                seen.insert(folder)
                groups.append((folder, []))
            }
            if let idx = groups.firstIndex(where: { $0.0 == folder }) {
                groups[idx].1.append(tab)
            }
        }
        return groups.map { TabGroup(folder: $0.0, tabs: $0.1) }
    }

    private func folderSection(_ group: TabGroup) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if expandedFolders.contains(group.folder) {
                        expandedFolders.remove(group.folder)
                    } else {
                        expandedFolders.insert(group.folder)
                    }
                }
            } label: {
                HStack(spacing: DeckSpace.s) {
                    Image(systemName: expandedFolders.contains(group.folder) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DeckColor.inkMuted)
                        .frame(width: 16)
                    Text(group.folder)
                        .deckFont(.legend)
                        .foregroundStyle(DeckColor.inkSecondary)
                    Text("\(group.tabs.count)")
                        .deckFont(.meta)
                        .foregroundStyle(DeckColor.inkFaint)
                    Spacer()
                }
                .padding(.horizontal, DeckSpace.m)
                .frame(minHeight: 36)
            }
            .buttonStyle(.plain)

            if expandedFolders.contains(group.folder) {
                ForEach(group.tabs, id: \.url) { tab in
                    browserTabRow(tab)
                }
            }
        }
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
                        let grouped = groupedTabs
                        ForEach(grouped, id: \.folder) { group in
                            if grouped.count == 1 && group.folder == "Tabs" {
                                // Single group, no folder header needed
                                ForEach(group.tabs, id: \.url) { tab in
                                    browserTabRow(tab)
                                }
                            } else {
                                folderSection(group)
                            }
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

    // MARK: - Popular Sites

    private let popularColumns = Array(repeating: GridItem(.flexible(), spacing: DeckSpace.s), count: 3)

    private var popularSitesTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DeckSpace.l) {
                ForEach(PopularSite.categories, id: \.self) { category in
                    VStack(alignment: .leading, spacing: DeckSpace.s) {
                        Text(category)
                            .deckFont(.meta)
                            .foregroundStyle(DeckColor.inkMuted)

                        LazyVGrid(columns: popularColumns, spacing: DeckSpace.s) {
                            ForEach(PopularSite.all.filter { $0.category == category }) { site in
                                popularSiteCell(site)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 72)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func popularSiteCell(_ site: PopularSite) -> some View {
        let isSelected = selectedPopularSite?.id == site.id
        return Button {
            selectedPopularSite = site
            label = site.name
            urlText = site.url
        } label: {
            VStack(spacing: 4) {
                Text(site.emoji)
                    .font(.system(size: 28))
                    .frame(width: 48, height: 48)
                    .background(
                        isSelected ? DeckColor.mint.opacity(0.12) : Color(hex: 0x2C2C2C),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                Text(site.name)
                    .deckFont(.meta)
                    .foregroundStyle(DeckColor.inkMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DeckSpace.s)
            .overlay {
                RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                    .strokeBorder(isSelected ? DeckColor.mint : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Key Combos

    private var keyComboTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DeckSpace.l) {
                ForEach(keyComboCategories, id: \.self) { category in
                    VStack(alignment: .leading, spacing: DeckSpace.s) {
                        Text(category)
                            .deckFont(.meta)
                            .foregroundStyle(DeckColor.inkMuted)

                        let presets = KeyComboPreset.all.filter { $0.category == category }
                        let cols = Array(repeating: GridItem(.flexible(), spacing: DeckSpace.s), count: 3)

                        LazyVGrid(columns: cols, spacing: DeckSpace.s) {
                            ForEach(presets) { preset in
                                keyComboCell(preset)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 72)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var keyComboCategories: [String] {
        var seen: [String] = []
        for preset in KeyComboPreset.all where !seen.contains(preset.category) {
            seen.append(preset.category)
        }
        return seen
    }

    private func keyComboCell(_ preset: KeyComboPreset) -> some View {
        let isSelected = selectedKeyCombo?.id == preset.id
        return Button {
            selectedKeyCombo = preset
            label = preset.name
        } label: {
            VStack(spacing: 4) {
                Image(systemName: preset.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? DeckColor.mint : DeckColor.ink)
                    .frame(width: 48, height: 48)
                    .background(
                        isSelected ? DeckColor.mint.opacity(0.12) : Color(hex: 0x2C2C2C),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                Text(preset.name)
                    .deckFont(.meta)
                    .foregroundStyle(DeckColor.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(preset.combo.uppercased().replacingOccurrences(of: "+", with: " + "))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(DeckColor.inkFaint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DeckSpace.s)
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

    private func selectTab(_ newTab: AddTileTab) {
        tab = newTab
        query = ""
        label = ""
        if newTab == .shortcuts {
            model.requestShortcuts()
        }
        if newTab == .openTabs {
            model.requestBrowserTabs()
        }
    }

    private var isURLValid: Bool { TileTarget.isValidWebsiteURL(urlText) }

    /// First selected app entry (for preview icon and single-select label).
    private var selectedAppEntry: AppCatalogEntry? {
        guard let first = selectedApps.first else { return nil }
        return model.catalog.first { $0.bundleID == first }
    }

    @State private var selectedPopularSite: PopularSite?

    private var target: TileTarget? {
        switch tab {
        case .apps:
            return selectedAppEntry.map { .app(bundleID: $0.bundleID) }
        case .shortcuts:
            return selectedShortcut.map { .shortcut(name: $0) }
        case .openTabs:
            return isURLValid ? .website(url: urlText.trimmingCharacters(in: .whitespaces)) : nil
        case .popular:
            return selectedPopularSite.map { .website(url: $0.url) }
        case .keys:
            return selectedKeyCombo.map { .keyCombo(combo: $0.combo) }
        }
    }

    private var previewTile: Tile {
        Tile(
            target: target ?? .app(bundleID: ""),
            label: label.isEmpty ? "Tile" : label,
            emoji: tab == .apps ? nil : emoji
        )
    }

    private var canAdd: Bool {
        switch tab {
        case .apps:
            return !selectedApps.isEmpty && model.nextSlot != nil
        case .shortcuts:
            return selectedShortcut != nil
                && model.nextSlot != nil
                && !label.trimmingCharacters(in: .whitespaces).isEmpty
        case .openTabs:
            return isURLValid
                && model.nextSlot != nil
                && !label.trimmingCharacters(in: .whitespaces).isEmpty
        case .popular:
            return selectedPopularSite != nil && model.nextSlot != nil
        case .keys:
            return selectedKeyCombo != nil && model.nextSlot != nil
        }
    }

    private func add() {
        switch tab {
        case .apps:
            for bundleID in selectedApps {
                guard let entry = model.catalog.first(where: { $0.bundleID == bundleID }) else { continue }
                model.add(Tile(target: .app(bundleID: bundleID), label: entry.name))
            }
        case .shortcuts:
            guard let target else { return }
            model.add(Tile(target: target, label: label.trimmingCharacters(in: .whitespaces)))
        case .openTabs:
            guard let target else { return }
            model.add(Tile(target: target, label: label.trimmingCharacters(in: .whitespaces)))
        case .popular:
            guard let site = selectedPopularSite else { return }
            model.add(Tile(target: .website(url: site.url), label: site.name, emoji: site.emoji))
        case .keys:
            guard let preset = selectedKeyCombo else { return }
            model.add(Tile(target: .keyCombo(combo: preset.combo), label: preset.name))
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

// MARK: - Popular Sites

struct PopularSite: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    let emoji: String
    let category: String

    init(_ name: String, url: String, emoji: String, category: String) {
        self.id = url
        self.name = name
        self.url = url
        self.emoji = emoji
        self.category = category
    }

    static let categories: [String] = ["Social", "Video", "Work", "Dev", "News", "Other"]

    static let all: [PopularSite] = [
        // Social
        PopularSite("YouTube", url: "https://youtube.com", emoji: "▶️", category: "Social"),
        PopularSite("X / Twitter", url: "https://x.com", emoji: "𝕏", category: "Social"),
        PopularSite("LinkedIn", url: "https://linkedin.com", emoji: "💼", category: "Social"),
        PopularSite("Instagram", url: "https://instagram.com", emoji: "📸", category: "Social"),
        PopularSite("Reddit", url: "https://reddit.com", emoji: "🤖", category: "Social"),
        PopularSite("TikTok", url: "https://tiktok.com", emoji: "🎵", category: "Social"),
        PopularSite("Facebook", url: "https://facebook.com", emoji: "👤", category: "Social"),
        PopularSite("Threads", url: "https://threads.net", emoji: "🧵", category: "Social"),
        PopularSite("WhatsApp", url: "https://web.whatsapp.com", emoji: "💬", category: "Social"),

        // Video
        PopularSite("Netflix", url: "https://netflix.com", emoji: "🎬", category: "Video"),
        PopularSite("Disney+", url: "https://disneyplus.com", emoji: "🏰", category: "Video"),
        PopularSite("Twitch", url: "https://twitch.tv", emoji: "🎮", category: "Video"),
        PopularSite("Spotify", url: "https://open.spotify.com", emoji: "🎧", category: "Video"),

        // Work
        PopularSite("Gmail", url: "https://mail.google.com", emoji: "📧", category: "Work"),
        PopularSite("Google Drive", url: "https://drive.google.com", emoji: "📁", category: "Work"),
        PopularSite("Google Docs", url: "https://docs.google.com", emoji: "📝", category: "Work"),
        PopularSite("Notion", url: "https://notion.so", emoji: "📓", category: "Work"),
        PopularSite("Slack", url: "https://app.slack.com", emoji: "💬", category: "Work"),
        PopularSite("Figma", url: "https://figma.com", emoji: "🎨", category: "Work"),
        PopularSite("Canva", url: "https://canva.com", emoji: "🖼️", category: "Work"),
        PopularSite("ChatGPT", url: "https://chat.openai.com", emoji: "🤖", category: "Work"),
        PopularSite("Claude", url: "https://claude.ai", emoji: "🧠", category: "Work"),

        // Dev
        PopularSite("GitHub", url: "https://github.com", emoji: "🐙", category: "Dev"),
        PopularSite("Stack Overflow", url: "https://stackoverflow.com", emoji: "📚", category: "Dev"),
        PopularSite("Vercel", url: "https://vercel.com", emoji: "▲", category: "Dev"),
        PopularSite("Supabase", url: "https://supabase.com", emoji: "⚡", category: "Dev"),
        PopularSite("NPM", url: "https://npmjs.com", emoji: "📦", category: "Dev"),
        PopularSite("Hacker News", url: "https://news.ycombinator.com", emoji: "🟧", category: "Dev"),

        // News
        PopularSite("BBC", url: "https://bbc.com", emoji: "📰", category: "News"),
        PopularSite("CNN", url: "https://cnn.com", emoji: "📺", category: "News"),
        PopularSite("The Verge", url: "https://theverge.com", emoji: "⚡", category: "News"),
        PopularSite("TechCrunch", url: "https://techcrunch.com", emoji: "💻", category: "News"),

        // Other
        PopularSite("Amazon", url: "https://amazon.com", emoji: "📦", category: "Other"),
        PopularSite("Google Maps", url: "https://maps.google.com", emoji: "🗺️", category: "Other"),
        PopularSite("Wikipedia", url: "https://wikipedia.org", emoji: "📖", category: "Other"),
        PopularSite("Pinterest", url: "https://pinterest.com", emoji: "📌", category: "Other"),
    ]
}
