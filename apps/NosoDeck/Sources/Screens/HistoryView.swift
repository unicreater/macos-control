import DeckKit
import SwiftUI

struct HistoryView: View {
    let model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red)
                    .frame(width: 120, height: 120)

                ForEach(model.macState.recents.reversed(), id: \.self) { bundleID in
                    let tile = Tile(target: .app(bundleID: bundleID), label: model.name(forBundleID: bundleID))
                    KeycapView(
                        tile: tile,
                        activity: model.macState.tileState(for: tile.target),
                        icon: model.icon(forBundleID: bundleID),
                        onTap: { model.activateRecent(bundleID) }
                    )
                    .frame(width: 120, height: 120)
                }
            }
            .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckColor.chassis)
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
