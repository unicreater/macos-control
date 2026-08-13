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

    var body: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            onTap()
        } label: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(
                        colors: activity == .frontmost
                            ? [Color(hex: 0x2A2A2A), Color(hex: 0x1E1E1E)]
                            : [Color(hex: 0x1E1E1E), Color(hex: 0x161616)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            activity == .frontmost ? DeckColor.mint.opacity(0.3) : Color(hex: 0x2A2A2A),
                            lineWidth: 1
                        )
                }
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

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 4) {
            iconView
                .frame(width: 72, height: 72)
                .overlay {
                    if activity == .frontmost {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(DeckColor.mint, lineWidth: 2)
                            .shadow(color: DeckColor.mint.opacity(0.4), radius: 8)
                            .frame(width: 76, height: 76)
                    }
                }
            Text(tile.label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(legendColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .textCase(.uppercase)
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if isDragging {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 24))
                .foregroundStyle(DeckColor.mint)
        } else if let emoji = tile.emoji, !emoji.isEmpty {
            Text(emoji)
                .font(.system(size: 38))
        } else if case .website(let url) = tile.target {
            // Website tile: show favicon
            AsyncImage(url: faviconURL(for: url)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 28))
                        .foregroundStyle(DeckColor.inkMuted)
                }
            }
        } else if let icon {
            icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(hex: 0x2A2A2A), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: 0x141414), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(Color(hex: 0x3A3A3A))
                        Text("ADD")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: 0x3A3A3A))
                    }
                }
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel("Add tile")
    }
}
