import AppKit
import CryptoKit
import DeckKit
import Foundation

/// The installed-app catalog the phone searches (FR-8), and the icons behind it (FR-7).
///
/// **Sandbox note.** The PRD's starter deck is "the Mac's Dock apps" (FR-12), but the
/// Dock's preferences live outside this app's container and are unreadable to a
/// sandboxed process — there is no MAS-legal way to ask what is in someone's Dock. The
/// suggestion list is therefore built from what is *running* right now, topped up from
/// a short list of common apps that are actually installed. That still satisfies FR-12's
/// acceptance criterion — a fresh pair shows a non-empty deck — and it is arguably a
/// better first guess than the Dock, which is often full of things nobody opens.
struct AppCatalogProvider {
    /// Where apps are looked for. Enumerating these is readable from the sandbox;
    /// the user's own folders are not searched and are not needed.
    private static let searchPaths = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities"
    ]

    /// Fallbacks for a first-run deck, in the order they would be offered. Only ones
    /// actually installed survive into the suggestion list.
    private static let commonBundleIDs = [
        "com.apple.Safari",
        "com.apple.mail",
        "com.apple.MobileSMS",
        "com.apple.Notes",
        "com.apple.iCal",
        "com.apple.Music",
        "com.apple.Photos",
        "com.apple.Terminal"
    ]

    private let iconSide: CGFloat = 256

    func catalog() -> Catalog {
        let apps = installedApps()
        return Catalog(apps: apps, suggested: suggestions(from: apps))
    }

    /// PNG bytes for an app's icon, at a size the phone can render at any tile scale.
    func iconPNG(forBundleID bundleID: String) -> Data? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return Self.png(from: NSWorkspace.shared.icon(forFile: url.path), side: iconSide)
    }

    // MARK: - Enumeration

    private func installedApps() -> [AppCatalogEntry] {
        var seen: Set<String> = []
        var entries: [AppCatalogEntry] = []

        for path in Self.searchPaths {
            let directory = URL(fileURLWithPath: path)
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in contents where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !seen.contains(bundleID) else { continue }
                // Never offer the agent itself as a tile.
                guard bundleID != Bundle.main.bundleIdentifier else { continue }

                seen.insert(bundleID)
                entries.append(AppCatalogEntry(
                    bundleID: bundleID,
                    name: Self.displayName(for: url, bundle: bundle),
                    iconHash: iconHash(forBundleID: bundleID)
                ))
            }
        }

        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func suggestions(from apps: [AppCatalogEntry]) -> [String] {
        let installed = Set(apps.map(\.bundleID))
        var ordered: [String] = []

        // Running apps first — the best available proxy for "what this person uses".
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier,
                  installed.contains(bundleID),
                  !ordered.contains(bundleID) else { continue }
            ordered.append(bundleID)
        }

        for bundleID in Self.commonBundleIDs
        where installed.contains(bundleID) && !ordered.contains(bundleID) {
            ordered.append(bundleID)
        }

        return Array(ordered.prefix(Page.maxTiles))
    }

    private static func displayName(for url: URL, bundle: Bundle) -> String {
        let info = bundle.localizedInfoDictionary ?? bundle.infoDictionary
        if let name = info?["CFBundleDisplayName"] as? String, !name.isEmpty { return name }
        if let name = info?["CFBundleName"] as? String, !name.isEmpty { return name }
        return url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Icons

    /// Hashing the rendered PNG rather than the file means the phone's cache invalidates
    /// exactly when the icon actually changes — an app update with the same artwork
    /// costs nothing.
    private func iconHash(forBundleID bundleID: String) -> String? {
        guard let data = iconPNG(forBundleID: bundleID) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func png(from image: NSImage, side: CGFloat) -> Data? {
        let size = NSSize(width: side, height: side)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(side),
            pixelsHigh: Int(side),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        representation.size = size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        return representation.representation(using: .png, properties: [:])
    }
}
