import DeckKit
import SwiftUI

/// S4 — the deck, in its M3 form: the real chrome and the real connection states around
/// an empty grid. The keycaps themselves arrive in M4.
///
/// The layout is fixed here rather than left for later because the grid is the one
/// non-negotiable in the design: 4×2, and it does not scale with device size.
struct DeckShellView: View {
    let model: AppModel

    /// The full Settings screen is S7, in M9. Until then the gear offers the one thing
    /// this milestone genuinely needs a way to reach: unpairing, so pairing can be
    /// tested more than once. Destructive, so it confirms (design S7).
    @State private var isConfirmingUnpair = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.bottom, 14)

            grid
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(model.session.state.deckOpacity)
                .disabled(!model.session.acceptsActions)
                .animation(DeckMotion.stateChange, value: model.session.state)

            bottomBar
                .padding(.top, DeckSpace.m)
        }
        .padding(.top, DeckGrid.topPadding)
        .padding(.bottom, DeckGrid.bottomPadding)
        .padding(.horizontal, DeckSpace.safeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckColor.chassis)
        .confirmationDialog(
            "Unpair \(model.connectedMacName ?? "this Mac")?",
            isPresented: $isConfirmingUnpair,
            titleVisibility: .visible
        ) {
            Button("Unpair", role: .destructive) { model.unpairCurrentMac() }
            Button("Keep paired", role: .cancel) {}
        } message: {
            Text("Your deck layout stays on this iPhone. You'll need a new PIN to reconnect.")
        }
    }

    private var topBar: some View {
        HStack(spacing: DeckSpace.m) {
            ConnectionBanner(
                state: model.session.state,
                macName: model.connectedMacName ?? "Mac",
                onRetry: { model.beginDiscovery() }
            )

            Spacer(minLength: DeckSpace.s)

            Button {
                isConfirmingUnpair = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(DeckColor.inkMuted)
                    .frame(width: 36, height: 36)
                    .background(Color(hex: 0x1C1C1C), in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                            .strokeBorder(Color(hex: 0x2C2C2C), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    /// 4×2, twelve-point gutters, filling whatever height is left. Every slot is the
    /// designed empty state — a dashed outline and "Add tile" — rather than a blank
    /// rectangle, because an empty deck still has to say what to do next.
    private var grid: some View {
        VStack(spacing: DeckGrid.gutter) {
            ForEach(0..<DeckGrid.rows, id: \.self) { row in
                HStack(spacing: DeckGrid.gutter) {
                    ForEach(0..<DeckGrid.columns, id: \.self) { column in
                        emptySlot
                            .accessibilityLabel("Empty slot \(row * DeckGrid.columns + column + 1)")
                    }
                }
            }
        }
    }

    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: DeckRadius.tile, style: .continuous)
            .strokeBorder(
                DeckColor.stroke,
                style: StrokeStyle(lineWidth: 2, dash: [6, 5])
            )
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

    private var bottomBar: some View {
        HStack(spacing: DeckSpace.s) {
            Spacer()
            Capsule()
                .fill(DeckColor.ink)
                .frame(width: 22, height: 5)
            Spacer()
        }
        .accessibilityHidden(true)
    }
}
