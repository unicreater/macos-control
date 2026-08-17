import DeckKit
import SwiftUI

/// A radial "painter palette" menu that fans out from a tile.
///
/// Appears on second tap of a frontmost app tile. Each petal is an action
/// the Mac can perform on the active app — media, navigation, scroll.
struct RadialMenuView: View {
    let onAction: (ActionKind) -> Void
    let onDismiss: () -> Void

    @State private var scrollDragOffset: CGFloat = 0
    @State private var lastScrollTick: CGFloat = 0

    private let items: [(icon: String, label: String, action: ActionKind)] = [
        ("backward.fill", "Back", .goBack),
        ("arrow.counterclockwise", "Refresh", .refreshPage),
        ("forward.fill", "Forward", .goForward),
        ("speaker.minus.fill", "Vol -", .volumeDown),
        ("playpause.fill", "Play", .mediaPlayPause),
        ("speaker.plus.fill", "Vol +", .volumeUp),
    ]

    // 3×2 grid layout
    private let columns = Array(repeating: GridItem(.fixed(72), spacing: 12), count: 3)

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            HStack(spacing: DeckSpace.m) {
                // Main actions panel
                VStack(spacing: DeckSpace.l) {
                    Text("Quick Actions")
                        .deckFont(.meta)
                        .foregroundStyle(DeckColor.inkMuted)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items, id: \.action) { item in
                            actionButton(icon: item.icon, label: item.label, action: item.action)
                        }
                    }

                    // Seek and media row
                    HStack(spacing: 12) {
                        actionPill(icon: "gobackward.5", label: "-5s", action: .seekBackward)
                        actionPill(icon: "backward.end.fill", label: "Prev", action: .mediaPreviousTrack)
                        actionPill(icon: "forward.end.fill", label: "Next", action: .mediaNextTrack)
                        actionPill(icon: "goforward.5", label: "+5s", action: .seekForward)
                    }

                    // Extra actions
                    HStack(spacing: 12) {
                        actionPill(icon: "xmark", label: "Close", action: .closeTab)
                        actionPill(icon: "plus", label: "New Tab", action: .newTab)
                        actionPill(icon: "speaker.slash.fill", label: "Mute", action: .volumeMute)
                    }

                    Button { onDismiss() } label: {
                        Text("Done")
                            .deckFont(.body)
                            .foregroundStyle(DeckColor.inkMuted)
                            .frame(maxWidth: 120, minHeight: 40)
                            .overlay {
                                Capsule().strokeBorder(Color(hex: 0x3A3A3A), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(DeckSpace.xl)
                .background(DeckColor.chassis.opacity(0.95), in: RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
                        .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
                }

                // Scroll track — press and slide
                scrollTrack
            }
            .padding(.horizontal, DeckSpace.m)
        }
    }

    // MARK: - Scroll track

    /// A vertical drag strip: slide up to scroll up, slide down to scroll down.
    /// Fires scroll events continuously as you drag.
    private var scrollTrack: some View {
        VStack(spacing: 4) {
            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(scrollDragOffset < -10 ? DeckColor.mint : DeckColor.inkFaint)

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DeckColor.surfaceRaised)
                .frame(width: 44)
                .overlay {
                    VStack(spacing: 6) {
                        Spacer()
                        // Thumb indicator
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(DeckColor.inkMuted)
                            .frame(width: 20, height: 4)
                            .offset(y: clampedThumbOffset)
                        Spacer()
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrollDragOffset = value.translation.height
                            let tickSize: CGFloat = 30
                            let ticks = (scrollDragOffset / tickSize).rounded(.towardZero)
                            if ticks != lastScrollTick {
                                lastScrollTick = ticks
                                if scrollDragOffset < 0 {
                                    onAction(.scrollUp)
                                } else {
                                    onAction(.scrollDown)
                                }
                            }
                        }
                        .onEnded { _ in
                            scrollDragOffset = 0
                            lastScrollTick = 0
                        }
                )

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(scrollDragOffset > 10 ? DeckColor.mint : DeckColor.inkFaint)
        }
        .padding(.vertical, DeckSpace.l)
    }

    private var clampedThumbOffset: CGFloat {
        min(max(scrollDragOffset * 0.3, -40), 40)
    }

    // MARK: - Buttons

    private func actionButton(icon: String, label: String, action: ActionKind) -> some View {
        Button {
            Haptics.tileTap()
            onAction(action)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(DeckColor.ink)
                    .frame(width: 52, height: 52)
                    .background(DeckColor.surfaceRaised, in: Circle())
                    .overlay {
                        Circle().strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
                    }
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(DeckColor.inkMuted)
            }
        }
        .buttonStyle(.plain)
    }

    private func actionPill(icon: String, label: String, action: ActionKind) -> some View {
        Button {
            Haptics.tileTap()
            onAction(action)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(DeckColor.ink)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(DeckColor.inkMuted)
            }
            .frame(width: 52, height: 44)
            .background(DeckColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                    .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
