import DeckKit
import SwiftUI

/// S2 — choose your Mac.
///
/// Portrait single-column layout. The empty state is never blank: while nothing has
/// been found, the screen still says it is scanning and lists what's usually wrong.
struct DiscoveryView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("NosoDeck")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(DeckColor.mint)
                    .padding(.bottom, DeckSpace.m)

                Text("Choose\nyour Mac")
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .foregroundStyle(DeckColor.ink)
                    .padding(.bottom, DeckSpace.xl)

                // Scanning status
                HStack(spacing: DeckSpace.s) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DeckColor.inkMuted)
                    Text(model.isScanning ? "Scanning your network…" : "Not scanning")
                        .deckFont(.bodySmall)
                        .foregroundStyle(DeckColor.inkMuted)
                }
                .padding(.bottom, DeckSpace.l)

                // Device list
                if model.discovered.isEmpty {
                    emptyState
                        .padding(.bottom, DeckSpace.xl)
                } else {
                    LazyVStack(spacing: DeckSpace.s) {
                        ForEach(model.discovered) { mac in
                            row(for: mac)
                        }
                    }
                    .padding(.bottom, DeckSpace.xl)
                }

                // Help card
                helpCard
            }
            .padding(.horizontal, DeckSpace.xl)
            .padding(.top, 48)
            .padding(.bottom, DeckSpace.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckColor.chassis)
    }

    private var emptyState: some View {
        VStack(spacing: DeckSpace.m) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundStyle(DeckColor.inkFaint)
            Text("Looking for your Mac…")
                .deckFont(.body)
                .foregroundStyle(DeckColor.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func row(for mac: DiscoveredMac) -> some View {
        let isPaired = model.pairing.trust.isTrusted(mac.identity)
        let isCompatible = mac.speaksOurProtocol

        return Button {
            model.select(mac)
        } label: {
            HStack(spacing: DeckSpace.m) {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(DeckColor.inkMuted)
                    .frame(width: 40, height: 40)
                    .background(Color(hex: 0x2C2C2C), in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))

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
            .background(DeckColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DeckRadius.tile, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DeckRadius.tile, style: .continuous)
                    .strokeBorder(isPaired ? DeckColor.mint : DeckColor.strokeSubtle, lineWidth: 1)
            }
            .opacity(isCompatible ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isCompatible)
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
        .padding(DeckSpace.l)
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
