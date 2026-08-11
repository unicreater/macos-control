import DeckKit
import Foundation
import Observation
import SwiftUI
import UIKit

/// Mac app icons, cached by content hash (FR-7).
///
/// Hash-addressed, so an icon is fetched once and never again — the catalog can be
/// refreshed as often as we like without re-sending artwork. Cached to disk too, so a
/// cold launch shows real icons before the Mac has even answered.
@MainActor
@Observable
final class IconCache {
    private var images: [String: Image] = [:]
    private var requested: Set<String> = []
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("NosoDeckIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The icon for a hash, loading it from disk on first ask. Nil means it has to be
    /// fetched from the Mac.
    func image(forHash hash: String?) -> Image? {
        guard let hash, !hash.isEmpty else { return nil }
        if let cached = images[hash] { return cached }

        guard let data = try? Data(contentsOf: fileURL(for: hash)),
              let uiImage = UIImage(data: data) else {
            return nil
        }
        let image = Image(uiImage: uiImage)
        images[hash] = image
        return image
    }

    func store(hash: String, png: Data) {
        guard let uiImage = UIImage(data: png) else { return }
        images[hash] = Image(uiImage: uiImage)
        requested.remove(hash)
        try? png.write(to: fileURL(for: hash), options: .atomic)
    }

    /// True the first time a hash is asked for, so the caller sends exactly one request
    /// per icon however many tiles happen to use it.
    func shouldRequest(hash: String?) -> Bool {
        guard let hash, !hash.isEmpty else { return false }
        guard image(forHash: hash) == nil, !requested.contains(hash) else { return false }
        requested.insert(hash)
        return true
    }

    private func fileURL(for hash: String) -> URL {
        // Hashes are hex from the agent; the filter keeps a hostile one from escaping
        // the cache directory.
        let safe = hash.filter { $0.isHexDigit }
        return directory.appendingPathComponent("\(safe).png")
    }
}
