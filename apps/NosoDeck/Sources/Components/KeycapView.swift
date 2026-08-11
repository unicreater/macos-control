import DeckKit
import SwiftUI

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fill)
            .clipShape(shape)
            .overlay { border }
            .overlay(alignment: .top) { topHighlight }
            .overlay(alignment: .topTrailing) { runningLED }
            .overlay(alignment: .topLeading) { removeBadge }
            .compositingGroup()
            .shadow(color: dropShadowColor, radius: dropShadowRadius, y: dropShadowOffset)
            .offset(y: isPressed ? 4 : 0)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(isDragging ? 1.04 : 1)
            .animation(reduceMotion ? nil : DeckMotion.tap, value: isPressed)
            .animation(reduceMotion ? nil : DeckMotion.stateChange, value: activity)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in state = true }
                    .onEnded { value in
                        // A tap, not a swipe: the quit gesture (FR-11) claims downward
                        // drags and lands in M5.
                        if abs(value.translation.height) < 20 && abs(value.translation.width) < 20 {
                            onTap()
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tile.label)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 9) {
            iconView
                .frame(width: 40, height: 40)
            Text(tile.label)
                .deckFont(.legend)
                .foregroundStyle(legendColor)
                // Legends truncate to one line and never reflow the grid.
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, DeckSpace.s)
    }

    @ViewBuilder
    private var iconView: some View {
        if isDragging {
            Text("Dragging")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.mint)
        } else if let emoji = tile.emoji, !emoji.isEmpty {
            // Shortcut and website tiles carry the emoji the user picked, at 34pt.
            Text(emoji)
                .font(.system(size: 34))
        } else if let icon {
            icon
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // Before the icon arrives: a neutral placeholder, never a broken image.
            RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous)
                .fill(Color(hex: 0x2C2C2C))
        }
    }

    // MARK: - The state table

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DeckRadius.tile, style: .continuous)
    }

    @ViewBuilder
    private var fill: some View {
        if isDragging {
            Color(hex: 0x1C1C1C)
        } else if isPressed {
            DeckColor.keycapPressed
        } else if activity == .frontmost {
            LinearGradient(
                colors: [DeckColor.keycapActiveTop, DeckColor.keycapActiveBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: [DeckColor.keycapTop, DeckColor.keycapBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var border: some View {
        if isDragging {
            shape.strokeBorder(DeckColor.mint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        } else if activity == .frontmost {
            // The frontmost ring: a mint border plus a soft 3pt halo.
            shape.strokeBorder(DeckColor.mint, lineWidth: 1)
                .background(shape.strokeBorder(DeckColor.mint.opacity(0.18), lineWidth: 3))
        } else if isPressed {
            shape.strokeBorder(Color(hex: 0x2A2A2A), lineWidth: 1)
        } else {
            shape.strokeBorder(DeckColor.stroke, lineWidth: 1)
        }
    }

    /// The inset highlight along the top edge. Absent when pressed — the cap has sunk.
    @ViewBuilder
    private var topHighlight: some View {
        if !isPressed && !isDragging {
            Rectangle()
                .fill(activity == .frontmost ? Color(hex: 0x444444) : DeckColor.keycapHighlight)
                .frame(height: 1)
                .padding(.horizontal, 2)
        }
    }

    /// Running is a mint LED, 8pt, inset 11pt from the top-right, with a glow. Colour is
    /// never the only cue — the LED is a shape, and VoiceOver says "running".
    @ViewBuilder
    private var runningLED: some View {
        if activity == .running || activity == .frontmost {
            Circle()
                .fill(DeckColor.mint)
                .frame(width: 8, height: 8)
                .shadow(color: DeckColor.mint, radius: 4)
                .padding(11)
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
            .offset(x: -7, y: -7)
            .accessibilityLabel("Remove \(tile.label)")
        }
    }

    private var legendColor: Color {
        if isPressed { return DeckColor.inkSecondary }
        if activity == .frontmost { return .white }
        return DeckColor.ink
    }

    private var rotation: Double {
        if isDragging { return -3 }
        guard isEditing, !reduceMotion else { return 0 }
        // Alternating ±0.8–1.5°, so a page of caps looks shaken loose rather than
        // uniformly skewed.
        return editIndex.isMultiple(of: 2) ? 1.1 : -0.9
    }

    private var dropShadowColor: Color {
        if isDragging { return .black.opacity(0.6) }
        if isPressed { return .clear }
        return DeckColor.keycapDrop
    }

    private var dropShadowRadius: CGFloat { isDragging ? 26 : 0 }
    private var dropShadowOffset: CGFloat { isDragging ? 12 : 3 }

    private var accessibilityValue: String {
        switch activity {
        case .frontmost: return "Frontmost"
        case .running: return "Running"
        case .idle: return "Not running"
        }
    }
}

/// The empty slot: dashed outline, a plus, and the words. An empty deck still has to
/// say what to do next.
struct EmptySlotView: View {
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: DeckRadius.tile, style: .continuous)
                .strokeBorder(DeckColor.stroke, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    VStack(spacing: DeckSpace.s) {
                        Image(systemName: "plus")
                            .foregroundStyle(DeckColor.inkFaint)
                        Text("Add tile")
                            .deckFont(.legend)
                            .foregroundStyle(DeckColor.inkFaint)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add tile")
    }
}
