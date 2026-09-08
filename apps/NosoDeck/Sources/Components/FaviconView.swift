import SwiftUI
import UIKit

/// In-memory + disk cache for favicons.
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()

    private var memory: [String: UIImage] = [:]
    private var loading: Set<String> = []
    private let directory: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("NosoDeckFavicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for host: String) -> UIImage? {
        if let cached = memory[host] { return cached }
        let file = directory.appendingPathComponent(safeFilename(host))
        guard let data = try? Data(contentsOf: file), let img = UIImage(data: data) else { return nil }
        memory[host] = img
        return img
    }

    func store(_ image: UIImage, for host: String) {
        memory[host] = image
        let file = directory.appendingPathComponent(safeFilename(host))
        try? image.pngData()?.write(to: file, options: .atomic)
    }

    func isLoading(_ host: String) -> Bool { loading.contains(host) }
    func startLoading(_ host: String) { loading.insert(host) }
    func finishLoading(_ host: String) { loading.remove(host) }

    private func safeFilename(_ host: String) -> String {
        let safe = host.replacingOccurrences(of: ".", with: "_")
        return "\(safe).png"
    }
}

/// Loads a website favicon with fallback chain and caching.
struct FaviconView: View {
    let urlString: String
    let iconRadius: CGFloat

    @State private var loadedImage: UIImage?
    @State private var didLoad = false

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
            } else if !didLoad {
                Color.clear
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 36))
                    .foregroundStyle(DeckColor.inkMuted)
            }
        }
        .onAppear {
            // Sync cache check — instant, no flicker
            if let host, let cached = FaviconCache.shared.image(for: host) {
                loadedImage = cached
                didLoad = true
            }
        }
        .task(id: urlString) {
            guard loadedImage == nil else { return }
            await loadFavicon()
        }
    }

    private func loadFavicon() async {
        guard let host else {
            didLoad = true
            return
        }

        // Double-check cache (might have loaded between onAppear and task start)
        if let cached = FaviconCache.shared.image(for: host) {
            loadedImage = cached
            didLoad = true
            return
        }

        // Don't duplicate fetches
        guard !FaviconCache.shared.isLoading(host) else {
            // Wait for the other fetch to finish, then check cache
            try? await Task.sleep(for: .seconds(2))
            if let cached = FaviconCache.shared.image(for: host) {
                loadedImage = cached
            }
            didLoad = true
            return
        }

        FaviconCache.shared.startLoading(host)

        // 1. apple-touch-icon
        if let img = await fetchImage("https://\(host)/apple-touch-icon.png") {
            FaviconCache.shared.store(img, for: host)
            FaviconCache.shared.finishLoading(host)
            loadedImage = img
            didLoad = true
            return
        }

        // 2. Google faviconV2
        let googleURL = "https://t3.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://\(host)&size=256"
        if let img = await fetchImage(googleURL) {
            FaviconCache.shared.store(img, for: host)
            FaviconCache.shared.finishLoading(host)
            loadedImage = img
            didLoad = true
            return
        }

        FaviconCache.shared.finishLoading(host)
        didLoad = true
    }

    private func fetchImage(_ urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let img = UIImage(data: data), img.size.width >= 16 else { return nil }
            return img
        } catch {
            return nil
        }
    }
}
