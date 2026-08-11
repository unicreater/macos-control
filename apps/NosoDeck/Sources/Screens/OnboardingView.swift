import DeckKit
import SwiftUI

/// S1 — two steps, no tour, no account. Skipped entirely when a Mac is already known
/// (FR-22).
struct OnboardingView: View {
    let model: AppModel

    @State private var step = 1

    var body: some View {
        HStack(alignment: .center, spacing: 36) {
            leftColumn
            rightColumn
        }
        .padding(.vertical, DeckSpace.xl)
        .padding(.horizontal, DeckSpace.safeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckColor.chassis)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: DeckSpace.l) {
            Text("Step \(step) / 2")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.inkMuted)

            Text(step == 1 ? "Install NosoDeck on your Mac" : "Pair this iPhone")
                .deckFont(.display)
                .foregroundStyle(DeckColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(step == 1
                 ? "Same Wi-Fi, that's it — no account, no cable."
                 : "We find your Mac on the local network and swap a 6-digit PIN.")
                .deckFont(.body)
                .foregroundStyle(DeckColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DeckSpace.m) {
                primaryButton(step == 1 ? "Continue" : "Find my Mac") {
                    if step == 1 {
                        step = 2
                    } else {
                        // Starting the browse is what raises the system prompt, which
                        // is why it happens here and not a moment earlier (FR-24).
                        model.beginDiscovery()
                    }
                }
                if step == 1 {
                    secondaryButton("Already installed") { step = 2 }
                }
            }

            pageDots
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var rightColumn: some View {
        if step == 1 {
            VStack(spacing: DeckSpace.l) {
                // Placeholder for the real App Store link (design: Assets).
                RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                    .fill(.white)
                    .frame(width: 132, height: 132)
                    .overlay {
                        Text("QR")
                            .deckFont(.meta)
                            .foregroundStyle(.black)
                    }
                Text("nosodeck.app/mac")
                    .deckFont(.legend)
                    .foregroundStyle(DeckColor.inkMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0x1C1C1C), Color(hex: 0x151515)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
                    .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
            }
        } else {
            PrePromptCard(kind: .localNetwork) {
                model.beginDiscovery()
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: DeckSpace.s) {
            ForEach(1...2, id: \.self) { index in
                Capsule()
                    .fill(index == step ? DeckColor.ink : Color(hex: 0x333333))
                    .frame(width: 22, height: 5)
            }
        }
        .accessibilityHidden(true)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .deckFont(.legend)
                .foregroundStyle(DeckColor.onOchre)
                .padding(.horizontal, DeckSpace.xl)
                .frame(minHeight: 48)
                .background(DeckColor.ochre, in: RoundedRectangle(cornerRadius: DeckRadius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .deckFont(.body)
                .foregroundStyle(Color(hex: 0x9A9A9A))
                .padding(.horizontal, DeckSpace.l)
                .frame(minHeight: 48)
                .overlay {
                    RoundedRectangle(cornerRadius: DeckRadius.tile, style: .continuous)
                        .strokeBorder(DeckColor.stroke, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}
