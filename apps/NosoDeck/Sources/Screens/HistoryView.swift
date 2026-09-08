import DeckKit
import SwiftUI

struct HistoryView: View {
    let model: AppModel

    private var isLandscape: Bool { model.isLandscapeLayout }

    private var allRecents: [String] {
        model.macState.recents.reversed()
    }

    private var unpinnedRecents: [String] {
        allRecents.filter { !model.isRecentPinned($0) }
    }

    private var pinnedRecents: [String] {
        model.pinnedRecents.filter { allRecents.contains($0) }
    }

    var body: some View {
        GeometryReader { geo in
            let portraitW = geo.size.width
            let portraitH = geo.size.height
            let contentW = isLandscape ? portraitH : portraitW
            let contentH = isLandscape ? portraitW : portraitH
            let tileSize = (isLandscape ? contentH : contentW) * 0.38

            Group {
                if isLandscape {
                    landscapeLayout(contentW: contentW, contentH: contentH, tileSize: tileSize)
                } else {
                    portraitLayout(contentW: contentW, contentH: contentH, tileSize: tileSize)
                }
            }
            .if(isLandscape) { view in
                view
                    .rotationEffect(.degrees(model.landscapeAngle))
                    .frame(width: portraitW, height: portraitH)
            }
        }
        .background(.clear)
    }

    // MARK: - Landscape: 60% unpinned | pill divider | 40% pinned

    private func landscapeLayout(contentW: CGFloat, contentH: CGFloat, tileSize: CGFloat) -> some View {
        HStack(spacing: 0) {
            if pinnedRecents.isEmpty {
                // No pins — full width unpinned
                recentScroll(items: unpinnedRecents, tileSize: tileSize, axis: .horizontal)
            } else {
                // Unpinned 60%
                recentScroll(items: unpinnedRecents, tileSize: tileSize, axis: .horizontal)
                    .frame(width: contentW * 0.58)

                // Pill divider
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 5, height: tileSize * 1.1)

                // Pinned 40%
                recentScroll(items: pinnedRecents, tileSize: tileSize, axis: .horizontal, pinned: true)
                    .frame(width: contentW * 0.38)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(width: contentW, height: contentH)
    }

    // MARK: - Portrait: unpinned center, pinned bottom-right

    private func portraitLayout(contentW: CGFloat, contentH: CGFloat, tileSize: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if pinnedRecents.isEmpty {
                recentScroll(items: unpinnedRecents, tileSize: tileSize, axis: .vertical)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Unpinned top 58%
                    recentScroll(items: unpinnedRecents, tileSize: tileSize, axis: .vertical)
                        .frame(maxWidth: .infinity)
                        .frame(height: contentH * 0.56)

                    // Pill divider horizontal
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: tileSize * 1.1, height: 5)

                    // Pinned bottom 40%
                    recentScroll(items: pinnedRecents, tileSize: tileSize * 0.85, axis: .vertical, pinned: true)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: contentW, height: contentH)
    }

    private func recentScroll(items: [String], tileSize: CGFloat, axis: Axis.Set, pinned: Bool = false) -> some View {
        ScrollView(axis, showsIndicators: false) {
            let layout = axis == .horizontal
                ? AnyLayout(HStackLayout(spacing: -tileSize * 0.25))
                : AnyLayout(VStackLayout(spacing: -tileSize * 0.25))

            layout {
                ForEach(Array(items.enumerated()), id: \.element) { index, bundleID in
                    recentTile(bundleID: bundleID, tileSize: tileSize)
                        .zIndex(Double(index))
                        .overlay(alignment: .topTrailing) {
                            if pinned { pinBadge }
                        }
                }
            }
            .padding(axis == .horizontal ? .horizontal : .vertical, 20)
        }
        .scrollEdgeEffectHidden(true)
    }

    // MARK: - Shared

    private func recentTile(bundleID: String, tileSize: CGFloat) -> some View {
        let deckEmoji = model.deck.pages.flatMap(\.tiles)
            .first(where: { $0.target == .app(bundleID: bundleID) })?.emoji
        let tile = Tile(
            target: .app(bundleID: bundleID),
            label: model.name(forBundleID: bundleID),
            emoji: deckEmoji
        )
        return KeycapView(
            tile: tile,
            activity: model.macState.tileState(for: tile.target),
            icon: model.icon(forBundleID: bundleID),
            onTap: { model.activateRecent(bundleID) }
        )
        .frame(width: tileSize, height: tileSize)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.togglePinRecent(bundleID)
                }
            }
        )
    }

    private var pinBadge: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 14))
            .foregroundStyle(.white)
    }
}

private extension View {
    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}

#if DEBUG
#Preview("History") {
    let model = AppModel.preview(
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
