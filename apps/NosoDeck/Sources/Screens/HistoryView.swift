import DeckKit
import SwiftUI

struct HistoryView: View {
    let model: AppModel

    var body: some View {
        GeometryReader { geo in
            let portraitW = geo.size.width
            let portraitH = geo.size.height
            let landscapeW = portraitH
            let landscapeH = portraitW
            let tileSize = landscapeH * 0.38

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -tileSize * 0.25) {
                    let recents = model.macState.recents.reversed() as [String]

                    ForEach(Array(recents.enumerated()), id: \.element) { index, bundleID in
                        let deckEmoji = model.deck.pages.flatMap(\.tiles)
                            .first(where: { $0.target == .app(bundleID: bundleID) })?.emoji
                        let tile = Tile(
                            target: .app(bundleID: bundleID),
                            label: model.name(forBundleID: bundleID),
                            emoji: deckEmoji
                        )
                        KeycapView(
                            tile: tile,
                            activity: model.macState.tileState(for: tile.target),
                            icon: model.icon(forBundleID: bundleID),
                            onTap: { model.activateRecent(bundleID) }
                        )
                        .frame(width: tileSize, height: tileSize)
                        .zIndex(Double(index))
                    }
                }
                .padding(.horizontal, 30)
            }
            .scrollEdgeEffectHidden(true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(width: landscapeW, height: landscapeH)
            .rotationEffect(.degrees(-90))
            .frame(width: portraitW, height: portraitH)
        }
        .background(.clear)
    }
}

#if DEBUG
#Preview("History") {
    let model = AppModel.preview(
        tiles: [
            Tile(target: .app(bundleID: "com.apple.Safari"), label: "Safari", emoji: "🧭"),
            Tile(target: .app(bundleID: "com.apple.Music"), label: "Music", emoji: "🎵"),
            Tile(target: .app(bundleID: "com.apple.Notes"), label: "Notes", emoji: "📝"),
            Tile(target: .app(bundleID: "com.apple.Xcode"), label: "Xcode", emoji: "🔨"),
            Tile(target: .app(bundleID: "com.apple.Terminal"), label: "Terminal", emoji: "🖥️"),
        ],
        macState: MacState(
            running: ["com.apple.Safari", "com.apple.Music", "com.apple.Notes", "com.apple.Xcode", "com.apple.Terminal"],
            frontmost: "com.apple.Xcode",
            recents: ["com.apple.Terminal", "com.apple.Safari", "com.apple.Music", "com.apple.Notes", "com.apple.Xcode"]
        )
    )
    HistoryView(model: model)
        .preferredColorScheme(.dark)
}
#endif
