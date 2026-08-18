import DeckKit
import SwiftUI

/// Context-aware quick-actions menu for the frontmost app.
///
/// Shows different actions based on the app type (browser, media, terminal, etc.).
/// Supports both portrait and landscape rotation.
struct RadialMenuView: View {
    let frontmostBundleID: String?
    let isLandscape: Bool
    let onAction: (ActionKind) -> Void
    let onDismiss: () -> Void

    @State private var scrollDragOffset: CGFloat = 0
    @State private var lastScrollTick: CGFloat = 0

    private var appCategory: AppCategory {
        guard let id = frontmostBundleID else { return .generic }
        return AppCategory.from(bundleID: id)
    }

    var body: some View {
        GeometryReader { geo in
            let portraitW = geo.size.width
            let portraitH = geo.size.height

            ZStack {
                // Backdrop — dismiss on tap
                Color.black.opacity(0.7)
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }

                // Menu panel
                menuContent
            }
            .frame(
                width: isLandscape ? portraitH : portraitW,
                height: isLandscape ? portraitW : portraitH
            )
            .if(isLandscape) { view in
                view
                    .rotationEffect(.degrees(-90))
                    .frame(width: portraitW, height: portraitH)
            }
        }
        .ignoresSafeArea()
    }

    private var menuContent: some View {
        HStack(spacing: DeckSpace.s) {
            VStack(spacing: DeckSpace.m) {
                // Category label
                HStack(spacing: 6) {
                    Image(systemName: appCategory.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(DeckColor.mint)
                    Text(appCategory.label)
                        .deckFont(.meta)
                        .foregroundStyle(DeckColor.inkMuted)
                }

                // Context actions grid
                let actions = appCategory.actions
                let cols = Array(repeating: GridItem(.fixed(66), spacing: 10), count: 3)

                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(actions) { item in
                        actionButton(icon: item.icon, label: item.label, action: item.action)
                    }
                }

                Button { onDismiss() } label: {
                    Text("Done")
                        .deckFont(.body)
                        .foregroundStyle(DeckColor.inkMuted)
                        .frame(maxWidth: 100, minHeight: 36)
                        .overlay {
                            Capsule().strokeBorder(Color(hex: 0x3A3A3A), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(DeckSpace.l)
            .background(DeckColor.chassis, in: RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
                    .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
            }

            scrollTrack
        }
        .padding(.horizontal, DeckSpace.m)
    }

    // MARK: - Scroll track

    private var scrollTrack: some View {
        VStack(spacing: 4) {
            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(scrollDragOffset < -10 ? DeckColor.mint : DeckColor.inkFaint)

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DeckColor.surfaceRaised)
                .frame(width: 40)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(DeckColor.inkMuted)
                        .frame(width: 16, height: 4)
                        .offset(y: min(max(scrollDragOffset * 0.3, -40), 40))
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
                                Haptics.scrollTick()
                                onAction(scrollDragOffset < 0 ? .scrollUp : .scrollDown)
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

    private func haptic(for action: ActionKind) {
        switch action {
        case .mediaPlayPause, .mediaNextTrack, .mediaPreviousTrack:
            Haptics.mediaAction()
        case .goBack, .goForward, .refreshPage, .closeTab, .newTab:
            Haptics.navAction()
        case .volumeUp, .volumeDown, .volumeMute:
            Haptics.volumeTick()
        case .seekForward, .seekBackward:
            Haptics.mediaAction()
        case .keyCombo:
            Haptics.keyComboFired()
        default:
            Haptics.tileTap()
        }
    }

    // MARK: - Buttons

    private func actionButton(icon: String, label: String, action: ActionKind) -> some View {
        Button {
            haptic(for: action)
            onAction(action)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(DeckColor.ink)
                    .frame(width: 46, height: 46)
                    .background(DeckColor.surfaceRaised, in: Circle())
                    .overlay {
                        Circle().strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
                    }
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(DeckColor.inkMuted)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View extension

private extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - App Categories

struct ActionItem: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let action: ActionKind
}

enum AppCategory {
    case browser
    case media
    case terminal
    case generic

    static func from(bundleID: String) -> AppCategory {
        let id = bundleID.lowercased()

        if id.contains("safari") || id.contains("chrome") || id.contains("firefox")
            || id.contains("browser") || id.contains("edge") || id.contains("brave")
            || id.contains("opera") || id.contains("vivaldi") || id.contains("arc") {
            return .browser
        }

        if id.contains("spotify") || id.contains("music") || id.contains("vlc")
            || id.contains("iina") || id.contains("youtube") || id.contains("netflix")
            || id.contains("tv") || id.contains("podcasts") || id.contains("plex") {
            return .media
        }

        if id.contains("terminal") || id.contains("iterm") || id.contains("warp")
            || id.contains("alacritty") || id.contains("kitty") || id.contains("hyper") {
            return .terminal
        }

        return .generic
    }

    var icon: String {
        switch self {
        case .browser: return "globe"
        case .media: return "music.note"
        case .terminal: return "terminal"
        case .generic: return "square.grid.2x2"
        }
    }

    var label: String {
        switch self {
        case .browser: return "BROWSER"
        case .media: return "MEDIA"
        case .terminal: return "TERMINAL"
        case .generic: return "QUICK ACTIONS"
        }
    }

    var actions: [ActionItem] {
        switch self {
        case .browser:
            return [
                ActionItem(icon: "chevron.left", label: "Back", action: .goBack),
                ActionItem(icon: "chevron.right", label: "Forward", action: .goForward),
                ActionItem(icon: "arrow.clockwise", label: "Refresh", action: .refreshPage),
                ActionItem(icon: "xmark", label: "Close", action: .closeTab),
                ActionItem(icon: "plus", label: "New Tab", action: .newTab),
                ActionItem(icon: "speaker.slash", label: "Mute", action: .volumeMute),
                ActionItem(icon: "gobackward.5", label: "-5s", action: .seekBackward),
                ActionItem(icon: "playpause", label: "Play", action: .mediaPlayPause),
                ActionItem(icon: "goforward.5", label: "+5s", action: .seekForward),
            ]
        case .media:
            return [
                ActionItem(icon: "backward.end.fill", label: "Prev", action: .mediaPreviousTrack),
                ActionItem(icon: "playpause.fill", label: "Play", action: .mediaPlayPause),
                ActionItem(icon: "forward.end.fill", label: "Next", action: .mediaNextTrack),
                ActionItem(icon: "gobackward.5", label: "-5s", action: .seekBackward),
                ActionItem(icon: "speaker.slash", label: "Mute", action: .volumeMute),
                ActionItem(icon: "goforward.5", label: "+5s", action: .seekForward),
                ActionItem(icon: "speaker.minus", label: "Vol -", action: .volumeDown),
                ActionItem(icon: "speaker.wave.2", label: "Vol", action: .volumeMute),
                ActionItem(icon: "speaker.plus", label: "Vol +", action: .volumeUp),
            ]
        case .terminal:
            return [
                ActionItem(icon: "doc.on.doc", label: "Copy", action: .copyClipboard),
                ActionItem(icon: "doc.on.clipboard", label: "Paste", action: .pasteClipboard),
                ActionItem(icon: "xmark", label: "Close", action: .closeTab),
                ActionItem(icon: "plus", label: "New Tab", action: .newTab),
                ActionItem(icon: "speaker.minus", label: "Vol -", action: .volumeDown),
                ActionItem(icon: "speaker.plus", label: "Vol +", action: .volumeUp),
            ]
        case .generic:
            return [
                ActionItem(icon: "chevron.left", label: "Back", action: .goBack),
                ActionItem(icon: "chevron.right", label: "Forward", action: .goForward),
                ActionItem(icon: "doc.on.doc", label: "Copy", action: .copyClipboard),
                ActionItem(icon: "doc.on.clipboard", label: "Paste", action: .pasteClipboard),
                ActionItem(icon: "playpause", label: "Play", action: .mediaPlayPause),
                ActionItem(icon: "speaker.slash", label: "Mute", action: .volumeMute),
                ActionItem(icon: "speaker.minus", label: "Vol -", action: .volumeDown),
                ActionItem(icon: "xmark", label: "Close", action: .closeTab),
                ActionItem(icon: "speaker.plus", label: "Vol +", action: .volumeUp),
            ]
        }
    }
}
