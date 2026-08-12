import Foundation

/// One installed Mac app, as offered to the phone's add-tile search (FR-8).
///
/// Icons travel separately, addressed by hash, so the catalog stays small and the phone
/// only fetches artwork it hasn't cached (PRD §5, `iconRequest`).
public struct AppCatalogEntry: Identifiable, Codable, Hashable, Sendable {
    public var bundleID: String
    public var name: String
    /// Hash of the app's PNG icon, or nil when the agent couldn't render one.
    public var iconHash: String?

    public init(bundleID: String, name: String, iconHash: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.iconHash = iconHash
    }

    public var id: String { bundleID }

    /// Case-insensitive substring match over name and bundle ID, so "saf" finds Safari
    /// and "com.apple.saf" does too. An empty query matches everything.
    public func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return name.range(of: trimmed, options: .caseInsensitive) != nil
            || bundleID.range(of: trimmed, options: .caseInsensitive) != nil
    }
}

extension Array where Element == AppCatalogEntry {
    /// Filters and orders search results: name-prefix matches first (so "saf" puts
    /// Safari above "Safari Technology Preview" rather than below something merely
    /// containing "saf"), then alphabetically.
    public func searching(_ query: String) -> [AppCatalogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = filter { $0.matches(query: trimmed) }
        guard !trimmed.isEmpty else {
            return matches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return matches.sorted { lhs, rhs in
            let lhsPrefix = lhs.name.range(of: trimmed, options: [.caseInsensitive, .anchored]) != nil
            let rhsPrefix = rhs.name.range(of: trimmed, options: [.caseInsensitive, .anchored]) != nil
            if lhsPrefix != rhsPrefix { return lhsPrefix }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
