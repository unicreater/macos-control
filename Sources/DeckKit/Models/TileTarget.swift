import Foundation

/// What a tile does when tapped. Mirrors the design handoff's `tile.kind`.
public enum TileKind: String, Codable, Sendable, CaseIterable {
    case app
    case shortcut
    case website
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

    public init(kind: TileKind, value: String) {
        switch kind {
        case .app: self = .app(bundleID: value)
        case .shortcut: self = .shortcut(name: value)
        case .website: self = .website(url: value)
        }
    }

    public var kind: TileKind {
        switch self {
        case .app: return .app
        case .shortcut: return .shortcut
        case .website: return .website
        }
    }

    /// The destination string, opaque to everything but the Mac-side executor.
    public var value: String {
        switch self {
        case .app(let bundleID): return bundleID
        case .shortcut(let name): return name
        case .website(let url): return url
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
