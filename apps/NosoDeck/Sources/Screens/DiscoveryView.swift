import DeckKit
import SwiftUI

/// S2 — choose your Mac.
///
/// The empty state is never blank: while nothing has been found, the screen still says
/// it is scanning and still lists the three things that are usually wrong.
struct DiscoveryView: View {
    let model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            deviceList
                .frame(maxWidth: .infinity, alignment: .leading)
            helpCard
                .frame(maxWidth: 300)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, DeckSpace.safeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DeckColor.chassis)
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            Text("Choose your Mac")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.inkMuted)

            ScrollView {
                LazyVStack(spacing: DeckSpace.s) {
                    ForEach(model.discovered) { mac in
                        row(for: mac)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            HStack(spacing: DeckSpace.s) {
                ProgressView()
                    .controlSize(.small)
                    .tint(DeckColor.inkMuted)
                Text(model.isScanning ? "Still scanning…" : "Not scanning")
                    .deckFont(.meta)
                    .foregroundStyle(DeckColor.inkMuted)
            }
        }
    }

    private func row(for mac: DiscoveredMac) -> some View {
        let isPaired = model.pairing.trust.isTrusted(mac.identity)
        let isCompatible = mac.speaksOurProtocol

        return Button {
            model.select(mac)
        } label: {
            HStack(spacing: DeckSpace.m) {
                RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous)
                    .fill(Color(hex: 0x2C2C2C))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(DeckColor.inkMuted)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(mac.name)
                        .deckFont(.body)
                        .foregroundStyle(DeckColor.ink)
                        .lineLimit(1)
                    Text(isCompatible ? (isPaired ? "Paired" : "Tap to pair") : "Needs a newer NosoDeck for Mac")
                        .deckFont(.bodySmall)
                        .foregroundStyle(DeckColor.inkMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: DeckSpace.s)

                if isPaired {
                    Text("Paired")
                        .deckFont(.meta)
                        .foregroundStyle(DeckColor.mint)
                        .padding(.horizontal, DeckSpace.s)
                        .padding(.vertical, DeckSpace.xs)
                        .overlay {
                            RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous)
                                .strokeBorder(DeckColor.mint, lineWidth: 1)
                        }
                } else if isCompatible {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(DeckColor.inkFaint)
                }
            }
            .padding(.horizontal, DeckSpace.m)
            .padding(.vertical, 14)
            .frame(minHeight: 52)
            .background(
                LinearGradient(
                    colors: [DeckColor.keycapTop, DeckColor.keycapBottom],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: DeckRadius.tile, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DeckRadius.tile, style: .continuous)
                    .strokeBorder(isPaired ? DeckColor.mint : DeckColor.stroke, lineWidth: 1)
            }
            // Offline and incompatible rows are dimmed and inert rather than hidden —
            // seeing the Mac and being told why it can't be used beats it vanishing.
            .opacity(isCompatible ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isCompatible)
        .accessibilityLabel(mac.name)
        .accessibilityValue(isPaired ? "Paired" : "Not paired")
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            Text("Nothing found?")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.inkMuted)

            VStack(alignment: .leading, spacing: DeckSpace.s) {
                check("NosoDeck is running on your Mac")
                check("Both devices are on the same Wi-Fi")
                check("Local network is allowed on both")
            }

            Button {
                model.beginDiscovery()
            } label: {
                Text("Scan again")
                    .deckFont(.body)
                    .foregroundStyle(DeckColor.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay {
                        RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                            .strokeBorder(Color(hex: 0x3A3A3A), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(DeckSpace.xl)
        .background(DeckColor.surface, in: RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
                .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
        }
    }

    private func check(_ text: String) -> some View {
        HStack(alignment: .top, spacing: DeckSpace.s) {
            Text("·")
                .foregroundStyle(DeckColor.inkFaint)
            Text(text)
                .deckFont(.bodySmall)
                .foregroundStyle(DeckColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
