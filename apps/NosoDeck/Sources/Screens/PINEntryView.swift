import DeckKit
import Foundation
import SwiftUI

/// S3 — PIN pairing.
///
/// The behavioural rule matters more than the layout: a wrong PIN shakes the row,
/// clears the digits in place, and decrements a **textual** counter. The flow never
/// resets, and the user never loses their position.
struct PINEntryView: View {
    let model: AppModel

    @FocusState private var isFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 36) {
            entryColumn
            statusColumn
        }
        .padding(.vertical, DeckSpace.xl)
        .padding(.horizontal, DeckSpace.safeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckColor.chassis)
        .onAppear { isFieldFocused = true }
    }

    private var entryColumn: some View {
        VStack(alignment: .leading, spacing: DeckSpace.l) {
            Text("Enter the PIN shown on your Mac")
                .deckFont(.title)
                .foregroundStyle(DeckColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            digitCells

            Text("Menu bar → NosoDeck icon")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.inkMuted)

            Button("Cancel") { model.cancelPairing() }
                .deckFont(.bodySmall)
                .foregroundStyle(DeckColor.inkMuted)
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var digitCells: some View {
        HStack(spacing: 10) {
            ForEach(0..<PairingPIN.length, id: \.self) { index in
                cell(at: index)
            }
        }
        // One invisible field takes the keyboard so paste and autofill work exactly
        // like typing; the cells are the visible half of the same control.
        .background {
            TextField("", text: pinBinding)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFieldFocused)
                // Not zero: a fully transparent field is unreliable to focus and tap.
                .opacity(0.01)
                .accessibilityLabel("Pairing PIN")
        }
        .contentShape(Rectangle())
        .onTapGesture { isFieldFocused = true }
        .modifier(ShakeEffect(shakes: reduceMotion ? 0 : CGFloat(model.shakeToken)))
        .animation(.linear(duration: 0.2), value: model.shakeToken)
        .opacity(reduceMotion && model.shakeToken > 0 ? 0.99 : 1)
    }

    private func cell(at index: Int) -> some View {
        let digits = Array(model.pinEntry)
        let isFilled = index < digits.count
        let isActive = index == digits.count

        return RoundedRectangle(cornerRadius: DeckRadius.tile, style: .continuous)
            .fill(fillStyle(isFilled: isFilled, isActive: isActive))
            .frame(width: 56, height: 74)
            .overlay {
                RoundedRectangle(cornerRadius: DeckRadius.tile, style: .continuous)
                    .strokeBorder(
                        isActive ? DeckColor.mint : DeckColor.strokeSubtle,
                        lineWidth: isActive ? 2 : 1
                    )
            }
            .overlay {
                if isFilled {
                    Text(String(digits[index]))
                        .font(.system(size: 30, weight: .regular, design: .monospaced))
                        .foregroundStyle(DeckColor.ink)
                }
            }
            .shadow(color: isActive ? DeckColor.mint.opacity(0.16) : .clear, radius: 3)
    }

    private func fillStyle(isFilled: Bool, isActive: Bool) -> AnyShapeStyle {
        if isFilled {
            return AnyShapeStyle(LinearGradient(
                colors: [DeckColor.keycapTop, DeckColor.keycapBottom],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
        return AnyShapeStyle(isActive ? Color(hex: 0x202020) : Color(hex: 0x181818))
    }

    @ViewBuilder
    private var statusColumn: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            if case .identityChanged(let identity) = model.pairing.state {
                identityChangedCard(identity)
            } else if let attemptsLeft = model.pairing.attemptsLeft {
                errorCard(attemptsLeft: attemptsLeft)
            } else {
                hintCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorCard(attemptsLeft: Int) -> some View {
        card(borderColor: DeckColor.red) {
            Text("Error")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.inkMuted)
            Text("Wrong PIN — \(attemptsLeft) \(attemptsLeft == 1 ? "try" : "tries") left")
                .deckFont(.body)
                .foregroundStyle(DeckColor.redInk)
            Text("Check the Mac's menu bar — the PIN changes after three wrong tries.")
                .deckFont(.bodySmall)
                .foregroundStyle(DeckColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func identityChangedCard(_ identity: DeviceIdentity) -> some View {
        card(borderColor: DeckColor.red) {
            Text("Identity changed")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.inkMuted)
            Text("\(identity.name) isn't the Mac you paired with before. It may have been reinstalled — or it may be a different machine using the same name.")
                .deckFont(.bodySmall)
                .foregroundStyle(DeckColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DeckSpace.m) {
                Button { model.confirmRePair() } label: {
                    Text("Re-pair")
                        .deckFont(.body)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(DeckColor.red, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)

                Button { model.cancelPairing() } label: {
                    Text("Cancel")
                        .deckFont(.body)
                        .foregroundStyle(DeckColor.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .overlay {
                            RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                                .strokeBorder(Color(hex: 0x3A3A3A), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hintCard: some View {
        card(borderColor: DeckColor.strokeSubtle) {
            Text("Where's the PIN?")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.inkMuted)
            Text("Click the NosoDeck icon in your Mac's menu bar. The six digits are at the top of the menu.")
                .deckFont(.bodySmall)
                .foregroundStyle(DeckColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card<Content: View>(
        borderColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DeckSpace.s) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DeckSpace.xl)
        .background(DeckColor.surface, in: RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
    }

    private var pinBinding: Binding<String> {
        Binding(
            get: { model.pinEntry },
            set: { model.updatePINEntry($0) }
        )
    }
}

/// Shakes horizontally, ~200ms, without moving anything else. Reduce Motion passes
/// zero, which makes it a no-op rather than a different animation.
private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(shakes * .pi * 3), y: 0))
    }
}
