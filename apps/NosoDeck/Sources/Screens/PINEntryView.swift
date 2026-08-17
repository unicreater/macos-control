import DeckKit
import Foundation
import SwiftUI

/// S3 — PIN pairing, Choclift-inspired layout.
///
/// Large headline, three setup steps with icons, four PIN cells,
/// and a capsule Connect button.
struct PINEntryView: View {
    let model: AppModel

    @FocusState private var isFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Brand
                    Text("NosoDeck")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(DeckColor.mint)
                        .padding(.bottom, DeckSpace.m)

                    // Headline
                    Text("Let's get\nconnected to\nyour Mac")
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .foregroundStyle(DeckColor.ink)
                        .padding(.bottom, 36)

                    // Steps
                    VStack(alignment: .leading, spacing: DeckSpace.xl) {
                        stepRow(
                            icon: "desktopcomputer",
                            text: "Install NosoDeck on your Mac and open it."
                        )
                        stepRow(
                            icon: "wifi",
                            text: "Make sure your Mac and iPhone are connected to the same Wi-Fi network."
                        )
                        stepRow(
                            icon: "number.square",
                            text: "Enter the 4-digit code shown in the Mac app below to connect."
                        )
                    }
                    .padding(.bottom, 36)

                    // PIN cells
                    digitCells
                        .id("pin")
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, DeckSpace.m)

                // Error / identity change
                statusInfo
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, DeckSpace.l)

                Spacer(minLength: 40)

                // Connect button
                Button {
                    isFieldFocused = true
                } label: {
                    Text("Connect")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DeckColor.chassis)
                        .frame(maxWidth: 220, minHeight: 52)
                        .background(DeckColor.mint, in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.bottom, DeckSpace.l)

                // Cancel
                Button { model.cancelPairing() } label: {
                    Text("Cancel")
                        .font(.system(size: 14))
                        .foregroundStyle(DeckColor.inkMuted)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.bottom, DeckSpace.xl)

                // Footer
                HStack(spacing: 4) {
                    Text("NosoDeck is an app by Owen Neo")
                        .foregroundStyle(DeckColor.inkFaint)
                    Button {
                        // TODO: link
                    } label: {
                        Text("Learn more")
                            .fontWeight(.medium)
                            .foregroundStyle(DeckColor.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity)
            }
                .padding(.horizontal, DeckSpace.xl)
                .padding(.top, 48)
                .padding(.bottom, DeckSpace.l)
            }
            .onChange(of: isFieldFocused) { _, focused in
                if focused {
                    withAnimation {
                        proxy.scrollTo("pin", anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckColor.chassis)
        .onAppear { isFieldFocused = true }
    }

    // MARK: - Steps

    private func stepRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: DeckSpace.m) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(DeckColor.inkMuted)
                .frame(width: 36, height: 36)

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(DeckColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - PIN cells

    private var digitCells: some View {
        HStack(spacing: 12) {
            ForEach(0..<PairingPIN.length, id: \.self) { index in
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

        return RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(
                isActive ? DeckColor.mint : DeckColor.strokeSubtle,
                lineWidth: isActive ? 2 : 1.5
            )
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isFilled ? DeckColor.surfaceRaised : .clear)
            )
            .frame(width: 72, height: 88)
            .overlay {
                if isFilled {
                    Text(String(digits[index]))
                        .font(.system(size: 36, weight: .medium, design: .monospaced))
                        .foregroundStyle(DeckColor.ink)
                }
            }
            .shadow(color: isActive ? DeckColor.mint.opacity(0.16) : .clear, radius: 4)
    }

    // MARK: - Status

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

#if DEBUG
#Preview("PIN Entry") {
    PINEntryView(model: .preview())
        .preferredColorScheme(.dark)
}
#endif

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
