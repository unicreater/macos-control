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
    var onTap: () -> Void = {}
    var onRemove: () -> Void = {}
    /// Swipe down on a running tile to quit that app (FR-11).
    var onQuit: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let iconRadius: CGFloat = 22

    var body: some View {
        Button {
            onTap()
        } label: {
            iconView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(4)
                .background(Color(hex: 0x1A1A1A).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: iconRadius + 4, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: iconRadius + 4, style: .continuous)
                        .strokeBorder(
                            activity == .frontmost
                                ? DeckColor.mint.opacity(0.5)
                                : Color.white.opacity(0.08),
                            lineWidth: activity == .frontmost ? 2 : 1
                        )
                }
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                .overlay(alignment: .topTrailing) { runningLED }
                .overlay(alignment: .topLeading) { removeBadge }
        }
        .buttonStyle(TileButtonStyle())
        .scaleEffect(isDragging ? 1.04 : 1)
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
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: iconRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: iconRadius, style: .continuous)
                .fill(Color(hex: 0x2A2A2A))
        }
    }

    private func faviconURL(for urlString: String) -> URL? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        // Google's favicon service — reliable and fast
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128")
    }

    /// Running is a mint LED, 8pt, top-right, with a glow.
    @ViewBuilder
    private var runningLED: some View {
        if activity == .running || activity == .frontmost {
            ZStack {
                Circle()
                    .fill(DeckColor.mint.opacity(0.2))
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(DeckColor.mint)
                    .frame(width: 8, height: 8)
                    .shadow(color: DeckColor.mint, radius: 4)
            }
            .padding(2)
        }
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

/// Press feedback — subtle scale + brightness shift. Spring physics for natural feel.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The empty slot: dashed outline, a plus, and the words. An empty deck still has to
/// say what to do next.
struct EmptySlotView: View {
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color(hex: 0x3A3A3A))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(4)
                .background(Color(hex: 0x141414).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.05), style: StrokeStyle(lineWidth: 1, dash: [8, 6]))
                }
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel("Add tile")
    }
}
