import DeckKit
import SwiftUI
import UIKit

/// The keycap — the core component.
///
/// Its bounds never change across states. Only fill, border, shadow and a 4pt vertical
/// offset vary, which is what makes the deck feel like hardware rather than a list of
/// buttons: nothing reflows when something lights up.
struct KeycapView: View {
    let tile: Tile
    let activity: TileActivityState
    var isEditing = false
    var isDragging = false
    /// Alternating tilt in edit mode; the caller passes the tile's index.
    var editIndex = 0
    /// The real Mac icon, once it has arrived from the agent (FR-7).
    var icon: Image?
    var shortcutColor: ShortcutInfo?
    var onTap: () -> Void = {}
    var onRemove: () -> Void = {}
    /// Swipe down on a running tile to quit that app (FR-11).
    var onQuit: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let iconRadius: CGFloat = 36

    var body: some View {
        Button {
            onTap()
        } label: {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height) * 0.8
                iconView
                    .frame(width: size, height: size)
                    .padding(1.5)
                    .background(
                        activity == .frontmost
                            ? Color.white.opacity(0.12)
                            : Color.white.opacity(0.05)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: iconRadius + 1, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: iconRadius + 1, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) { removeBadge }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(TileButtonStyle())
        .scaleEffect(isDragging ? 1.04 : 1)
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        .rotationEffect(.degrees(rotation))
        .animation(reduceMotion ? nil : DeckMotion.stateChange, value: activity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.label)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var iconView: some View {
        if isDragging {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 32))
                .foregroundStyle(DeckColor.mint)
        } else if let emoji = tile.emoji, !emoji.isEmpty {
            Text(emoji)
                .font(.system(size: 52))
        } else if case .keyCombo(let combo) = tile.target {
            let preset = KeyComboPreset.all.first { $0.combo == combo }
            Image(systemName: preset?.icon ?? "command")
                .font(.system(size: 32))
                .foregroundStyle(DeckColor.inkSecondary)
        } else if case .website(let url) = tile.target {
            AsyncImage(url: faviconURL(for: url)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: iconRadius, style: .continuous))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 36))
                        .foregroundStyle(DeckColor.inkMuted)
                }
            }
        } else if let icon {
            icon
                .renderingMode(.original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: iconRadius, style: .continuous))
        } else if let sc = shortcutColor {
            // Shortcut tile with color background and label
            RoundedRectangle(cornerRadius: iconRadius, style: .continuous)
                .fill(Color(red: Double(sc.colorR) / 255, green: Double(sc.colorG) / 255, blue: Double(sc.colorB) / 255))
                .overlay {
                    VStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(tile.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: iconRadius, style: .continuous)
                .fill(Color(hex: 0x2A2A2A))
        }
    }

    private func faviconURL(for urlString: String) -> URL? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        // icon.horse provides high-res favicons (apple-touch-icon when available)
        return URL(string: "https://icon.horse/icon/\(host)")
    }


    @ViewBuilder
    private var removeBadge: some View {
        if isEditing {
            Button(action: onRemove) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(DeckColor.red, in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: -4, y: -4)
            .accessibilityLabel("Remove \(tile.label)")
        }
    }

    private var legendColor: Color {
        if activity == .frontmost { return .white }
        return DeckColor.ink
    }

    private var rotation: Double {
        if isDragging { return -3 }
        guard isEditing, !reduceMotion else { return 0 }
        return editIndex.isMultiple(of: 2) ? 1.1 : -0.9
    }

    private var accessibilityValue: String {
        switch activity {
        case .frontmost: return "Frontmost"
        case .running: return "Running"
        case .idle: return "Not running"
        }
    }
}

/// Press feedback — scale only, no brightness change.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The empty slot: dashed outline, a plus, and the words. An empty deck still has to
/// say what to do next.
struct EmptySlotView: View {
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height) * 0.8
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.15))
                    .frame(width: size, height: size)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel("Add tile")
    }
}
