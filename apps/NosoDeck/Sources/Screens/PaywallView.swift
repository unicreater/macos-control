import DeckKit
import SwiftUI

/// S8 — the paywall.
///
/// The close button is full size, top-left, and present from the first frame. No timer,
/// no fake discount, no countdown. Premium is described as what it adds, because nothing
/// the free tier had is ever taken away (FR-17).
struct PaywallView: View {
    let store: EntitlementStore
    var reason: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .top, spacing: DeckSpace.xl) {
            VStack(alignment: .leading, spacing: DeckSpace.l) {
                closeButton

                Text("NosoDeck Premium")
                    .deckFont(.title)
                    .foregroundStyle(DeckColor.ink)

                if let reason {
                    Text(reason)
                        .deckFont(.body)
                        .foregroundStyle(DeckColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: DeckSpace.s) {
                    benefit("8 pages instead of 2")
                    benefit("The recents column")
                    benefit("Icon themes")
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            purchaseCard
                .frame(width: 320)
        }
        .padding(DeckSpace.xl)
        .padding(.horizontal, DeckSpace.safeInset - DeckSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckColor.chassis)
        .preferredColorScheme(.dark)
        .task { await store.start() }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DeckColor.inkSecondary)
                .frame(width: 44, height: 44)
                .background(DeckColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    private func benefit(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DeckSpace.s) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DeckColor.ochre)
            Text(text)
                .deckFont(.body)
                .foregroundStyle(DeckColor.inkSecondary)
        }
    }

    private var purchaseCard: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            Text("Premium")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.ochre)

            Text(store.trialDescription)
                .deckFont(.body)
                .foregroundStyle(DeckColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Cancel any time in the App Store.")
                .deckFont(.bodySmall)
                .foregroundStyle(DeckColor.inkMuted)

            Button {
                Task { await store.purchase() }
            } label: {
                Text(store.isPurchasing ? "Working…" : "Start free trial")
                    .deckFont(.legend)
                    .foregroundStyle(DeckColor.onOchre)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(DeckColor.ochre, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(store.isPurchasing)

            Button {
                Task { await store.restore() }
            } label: {
                Text("Restore purchases")
                    .deckFont(.bodySmall)
                    .foregroundStyle(DeckColor.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.plain)
            .disabled(store.isPurchasing)

            if let error = store.lastError {
                Text(error)
                    .deckFont(.bodySmall)
                    .foregroundStyle(DeckColor.redInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x221C0C), Color(hex: 0x1A1608)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
                .strokeBorder(DeckColor.ochre, lineWidth: 1)
        }
        .onChange(of: store.entitlement) { _, entitlement in
            // Unlocked: get out of the way immediately.
            if entitlement == .premium { dismiss() }
        }
    }
}
