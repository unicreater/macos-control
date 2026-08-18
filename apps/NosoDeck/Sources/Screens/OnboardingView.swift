import DeckKit
import SwiftUI

/// S1 — two steps, no tour, no account. Skipped entirely when a Mac is already known
/// (FR-22).
struct OnboardingView: View {
    let model: AppModel

    @State private var step = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("NosoDeck")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(DeckColor.mint)
                    .padding(.bottom, DeckSpace.m)

                Text(step == 1 ? "Install NosoDeck\non your Mac" : "Pair this\niPhone")
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .foregroundStyle(DeckColor.ink)
                    .padding(.bottom, DeckSpace.xl)

                Text(step == 1
                     ? "Same Wi-Fi, that's it — no account, no cable."
                     : "We find your Mac on the local network and swap a PIN.")
                    .deckFont(.body)
                    .foregroundStyle(DeckColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 36)

                if step == 1 {
                    qrCard
                        .padding(.bottom, 36)
                } else {
                    PrePromptCard(kind: .localNetwork) {
                        model.beginDiscovery()
                    }
                    .padding(.bottom, 36)
                }

                VStack(spacing: DeckSpace.m) {
                    primaryButton(step == 1 ? "Continue" : "Find my Mac") {
                        if step == 1 {
                            step = 2
                        } else {
                            model.beginDiscovery()
                        }
                    }

                    if step == 1 {
                        secondaryButton("Already installed") { step = 2 }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, DeckSpace.xl)

                pageDots
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, DeckSpace.xl)
            .padding(.top, 48)
            .padding(.bottom, DeckSpace.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckColor.chassis)
    }

    private var qrCard: some View {
        VStack(spacing: DeckSpace.l) {
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, DeckSpace.xl)
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
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DeckColor.chassis)
                .frame(maxWidth: 220, minHeight: 52)
                .background(DeckColor.mint, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .deckFont(.body)
                .foregroundStyle(DeckColor.inkMuted)
        }
        .buttonStyle(.plain)
    }
}
