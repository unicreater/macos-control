import SwiftUI
import UIKit

/// In-memory + disk cache for favicons so they don't re-fetch on every view rebuild.
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()

    private var memory: [String: UIImage] = [:]
    private var failed: Set<String> = []
    private let directory: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("NosoDeckFavicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for host: String) -> UIImage? {
        if let cached = memory[host] { return cached }
        let file = directory.appendingPathComponent("\(host.hashValue).png")
        guard let data = try? Data(contentsOf: file), let img = UIImage(data: data) else { return nil }
        memory[host] = img
        return img
    }

    func store(_ image: UIImage, for host: String) {
        memory[host] = image
        let file = directory.appendingPathComponent("\(host.hashValue).png")
        try? image.pngData()?.write(to: file, options: .atomic)
    }

    func hasFailed(_ host: String) -> Bool { failed.contains(host) }
    func markFailed(_ host: String) { failed.insert(host) }
}

/// Loads a website favicon with fallback chain and caching.
struct FaviconView: View {
    let urlString: String
    let iconRadius: CGFloat

    @State private var loadedImage: UIImage?
    @State private var isLoading = true

    private var host: String? {
        URL(string: urlString)?.host
    }

    var body: some View {
        Group {
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: iconRadius, style: .continuous))
            } else if isLoading {
                ProgressView()
                    .tint(DeckColor.inkFaint)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 36))
                    .foregroundStyle(DeckColor.inkMuted)
            }
        }
        .task(id: urlString) {
            await loadFavicon()
        }
    }

    private func loadFavicon() async {
        guard let host else {
            isLoading = false
            return
        }

        // Check cache first
        if let cached = FaviconCache.shared.image(for: host) {
            loadedImage = cached
            isLoading = false
            return
        }

        // Skip if previously failed
        if FaviconCache.shared.hasFailed(host) {
            isLoading = false
            return
        }

        // 1. apple-touch-icon
        if let img = await fetchImage("https://\(host)/apple-touch-icon.png"), img.size.width >= 48 {
            FaviconCache.shared.store(img, for: host)
            loadedImage = img
            isLoading = false
            return
        }

        // 2. Google faviconV2
        let googleURL = "https://t3.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://\(host)&size=256"
        if let img = await fetchImage(googleURL), img.size.width >= 32 {
            FaviconCache.shared.store(img, for: host)
            loadedImage = img
            isLoading = false
            return
        }

        FaviconCache.shared.markFailed(host)
        isLoading = false
    }

    private func fetchImage(_ urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
