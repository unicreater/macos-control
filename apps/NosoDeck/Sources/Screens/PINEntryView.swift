import DeckKit
import Foundation
import SwiftUI

/// S3 — PIN pairing.
///
/// Optimized for landscape: single centered column with compact digit cells.
/// The hint card only shows on error or identity change — not by default,
/// freeing vertical space for the PIN entry itself.
struct PINEntryView: View {
    let model: AppModel

    @FocusState private var isFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: DeckSpace.m) {
                Text("Enter PIN from your Mac")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(DeckColor.ink)

                digitCells

                // Error or identity change — shown inline below the cells
                statusInfo

                Button("Cancel") { model.cancelPairing() }
                    .font(.system(size: 14))
                    .foregroundStyle(DeckColor.inkMuted)
                    .buttonStyle(.plain)
                    .padding(.top, DeckSpace.xs)
            }

            Spacer()
        }
        .padding(.horizontal, DeckSpace.safeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckColor.chassis)
        .onAppear { isFieldFocused = true }
    }

    private var digitCells: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                cell(at: index)
            }
            // Visual gap between groups of 3
            Spacer().frame(width: 12)
            ForEach(3..<6, id: \.self) { index in
                cell(at: index)
            }
        }
        .background {
            TextField("", text: pinBinding)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFieldFocused)
                .opacity(0.01)
                .accessibilityLabel("Pairing PIN")
        }
        .contentShape(Rectangle())
        .onTapGesture { isFieldFocused = true }
        .modifier(ShakeEffect(shakes: reduceMotion ? 0 : CGFloat(model.shakeToken)))
        .animation(.linear(duration: 0.2), value: model.shakeToken)
    }

    private func cell(at index: Int) -> some View {
        let digits = Array(model.pinEntry)
        let isFilled = index < digits.count
        let isActive = index == digits.count

        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(fillStyle(isFilled: isFilled, isActive: isActive))
            .frame(width: 64, height: 72)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isActive ? DeckColor.mint : DeckColor.strokeSubtle,
                        lineWidth: isActive ? 2 : 1
                    )
            }
            .overlay {
                if isFilled {
                    Text(String(digits[index]))
                        .font(.system(size: 32, weight: .medium, design: .monospaced))
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
    private var statusInfo: some View {
        if case .identityChanged(let identity) = model.pairing.state {
            identityChangedBanner(identity)
        } else if let attemptsLeft = model.pairing.attemptsLeft {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(DeckColor.red)
                    .font(.system(size: 14))
                Text("Wrong PIN — \(attemptsLeft) \(attemptsLeft == 1 ? "try" : "tries") left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DeckColor.redInk)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(DeckColor.redBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func identityChangedBanner(_ identity: DeviceIdentity) -> some View {
        VStack(spacing: DeckSpace.s) {
            Text("\(identity.name) isn't the Mac you paired with before.")
                .font(.system(size: 13))
                .foregroundStyle(DeckColor.inkSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: DeckSpace.m) {
                Button { model.confirmRePair() } label: {
                    Text("Re-pair")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(minWidth: 80, minHeight: 36)
                        .background(DeckColor.red, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button { model.cancelPairing() } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DeckColor.inkSecondary)
                        .frame(minWidth: 80, minHeight: 36)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(hex: 0x3A3A3A), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(DeckColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DeckColor.red.opacity(0.5), lineWidth: 1)
        }
    }

    private var pinBinding: Binding<String> {
        Binding(
            get: { model.pinEntry },
            set: { model.updatePINEntry($0) }
        )
    }
}

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
