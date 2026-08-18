import Foundation

/// What a tile does when tapped. Mirrors the design handoff's `tile.kind`.
public enum TileKind: String, Codable, Sendable, CaseIterable {
    case app
    case shortcut
    case website
    case keyCombo
}

/// Where a tile points. The `kind` + `value` pair is what travels on the wire and what
/// gets persisted, so the two stay in sync by construction.
public enum TileTarget: Hashable, Sendable {
    /// A Mac app, identified by bundle ID (FR-9).
    case app(bundleID: String)
    /// An Apple Shortcut on the Mac, identified by name (FR-13).
    case shortcut(name: String)
    /// A URL opened in the Mac's default browser (FR-14).
    case website(url: String)
    /// A keyboard shortcut sent to the Mac (e.g., "cmd+shift+3").
    case keyCombo(combo: String)

    public init(kind: TileKind, value: String) {
        switch kind {
        case .app: self = .app(bundleID: value)
        case .shortcut: self = .shortcut(name: value)
        case .website: self = .website(url: value)
        case .keyCombo: self = .keyCombo(combo: value)
        }
    }

    public var kind: TileKind {
        switch self {
        case .app: return .app
        case .shortcut: return .shortcut
        case .website: return .website
        case .keyCombo: return .keyCombo
        }
    }

    /// The destination string, opaque to everything but the Mac-side executor.
    public var value: String {
        switch self {
        case .app(let bundleID): return bundleID
        case .shortcut(let name): return name
        case .website(let url): return url
        case .keyCombo(let combo): return combo
        }
    }

    /// Inline validation for the website tab of the add-tile flow (design S6): the
    /// **ADD** button dims rather than disappears while this is false.
    public static func isValidWebsiteURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let components = URLComponents(string: trimmed) else { return false }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = components.host, !host.isEmpty else { return false }
        return true
    }
}

extension TileTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(TileKind.self, forKey: .kind)
        let value = try container.decode(String.self, forKey: .value)
        self.init(kind: kind, value: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(value, forKey: .value)
    }
}

/// Predefined keyboard shortcut presets.
public struct KeyComboPreset: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let combo: String
    public let icon: String
    public let category: String

    public init(name: String, combo: String, icon: String, category: String) {
        self.id = combo
        self.name = name
        self.combo = combo
        self.icon = icon
        self.category = category
    }

    public static let all: [KeyComboPreset] = [
        // Screenshots
        KeyComboPreset(name: "Screenshot (Full)", combo: "cmd+shift+3", icon: "camera.viewfinder", category: "Screenshots"),
        KeyComboPreset(name: "Screenshot (Area)", combo: "cmd+shift+4", icon: "crop", category: "Screenshots"),
        KeyComboPreset(name: "Screen Capture", combo: "cmd+shift+5", icon: "rectangle.dashed.badge.record", category: "Screenshots"),

        // System
        KeyComboPreset(name: "Lock Screen", combo: "ctrl+cmd+q", icon: "lock", category: "System"),
        KeyComboPreset(name: "Force Quit", combo: "cmd+alt+esc", icon: "xmark.app", category: "System"),
        KeyComboPreset(name: "Spotlight", combo: "cmd+space", icon: "magnifyingglass", category: "System"),
        KeyComboPreset(name: "Mission Control", combo: "ctrl+up", icon: "rectangle.3.group", category: "System"),

        // Window
        KeyComboPreset(name: "Close Window", combo: "cmd+w", icon: "xmark.square", category: "Window"),
        KeyComboPreset(name: "Minimize", combo: "cmd+m", icon: "arrow.down.right.and.arrow.up.left", category: "Window"),
        KeyComboPreset(name: "Fullscreen", combo: "ctrl+cmd+f", icon: "arrow.up.left.and.arrow.down.right", category: "Window"),
        KeyComboPreset(name: "Hide App", combo: "cmd+h", icon: "eye.slash", category: "Window"),
        KeyComboPreset(name: "Quit App", combo: "cmd+q", icon: "power", category: "Window"),

        // Editing
        KeyComboPreset(name: "Undo", combo: "cmd+z", icon: "arrow.uturn.backward", category: "Editing"),
        KeyComboPreset(name: "Redo", combo: "cmd+shift+z", icon: "arrow.uturn.forward", category: "Editing"),
        KeyComboPreset(name: "Select All", combo: "cmd+a", icon: "selection.pin.in.out", category: "Editing"),
        KeyComboPreset(name: "Find", combo: "cmd+f", icon: "doc.text.magnifyingglass", category: "Editing"),
        KeyComboPreset(name: "Save", combo: "cmd+s", icon: "square.and.arrow.down", category: "Editing"),
    ]
}
