import DeckKit
import SwiftUI

/// S7 — Settings.
///
/// Portrait: single-column scrollable. Landscape: two-column side-by-side.
/// No header/back arrow — it's a tab, not a pushed screen.
struct SettingsView: View {
    let model: AppModel

    @State private var isConfirmingUnpair = false

    private var isPortrait: Bool { !model.isLandscapeLayout }

    var body: some View {
        ScrollView {
            if isPortrait {
                portraitLayout
            } else {
                landscapeLayout
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    // MARK: - Layouts

    private var portraitLayout: some View {
        VStack(spacing: DeckSpace.l) {
            versionLabel
            deviceCard
            premiumCard
            deckCard
            rowList
        }
        .padding(.horizontal, DeckSpace.l)
        .padding(.vertical, DeckSpace.l)
    }

    private var landscapeLayout: some View {
        VStack(alignment: .leading, spacing: DeckSpace.l) {
            versionLabel

            HStack(alignment: .top, spacing: DeckSpace.l) {
                VStack(spacing: DeckSpace.l) {
                    deviceCard
                    deckCard
                    Spacer(minLength: 0)
                }
                VStack(spacing: DeckSpace.l) {
                    premiumCard
                    rowList
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, DeckSpace.l)
        .padding(.horizontal, DeckSpace.safeInset)
    }

    // MARK: - Cards

    private var versionLabel: some View {
        HStack {
            Text("Settings")
                .deckFont(.title)
                .foregroundStyle(DeckColor.ink)
            Spacer()
            Text("v\(AppInfo.versionString)")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.inkFaint)
        }
    }

    private var deviceCard: some View {
        card {
            HStack(spacing: DeckSpace.m) {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(DeckColor.inkMuted)
                    .frame(width: 40, height: 40)
                    .background(Color(hex: 0x2C2C2C), in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.connectedMacName ?? "No Mac paired")
                        .deckFont(.body)
                        .foregroundStyle(DeckColor.ink)
                        .lineLimit(1)
                    Text(connectionSummary)
                        .deckFont(.bodySmall)
                        .foregroundStyle(model.session.state.isLive ? DeckColor.mint : DeckColor.inkMuted)
                }

                Spacer(minLength: DeckSpace.s)

                if model.pairing.isPaired {
                    Button { isConfirmingUnpair = true } label: {
                        Text("Unpair")
                            .deckFont(.legend)
                            .foregroundStyle(DeckColor.redInk)
                            .padding(.horizontal, DeckSpace.m)
                            .frame(height: 36)
                            .overlay {
                                RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                                    .strokeBorder(DeckColor.red, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { model.startPairing() } label: {
                        Text("Pair Mac")
                            .deckFont(.legend)
                            .foregroundStyle(DeckColor.onMint)
                            .padding(.horizontal, DeckSpace.m)
                            .frame(height: 36)
                            .background(DeckColor.mint, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var deckCard: some View {
        card {
            VStack(alignment: .leading, spacing: DeckSpace.m) {
                Text("Deck")
                    .deckFont(.meta)
                    .foregroundStyle(DeckColor.inkMuted)

                toggle(
                    title: "Emoji insertion",
                    explainer: "Needs Accessibility on the Mac. Off = tiles still launch apps; only typed emoji stops working.",
                    isOn: Binding(
                        get: { model.isEmojiStripEnabled },
                        set: { model.setEmojiStripEnabled($0) }
                    )
                )

                Divider().overlay(DeckColor.strokeSubtle)

                toggle(
                    title: "Keep screen awake while connected",
                    explainer: "Off = screen dims on its usual schedule.",
                    isOn: Binding(
                        get: { model.keepsScreenAwake },
                        set: { model.setKeepsScreenAwake($0) }
                    )
                )

                Divider().overlay(DeckColor.strokeSubtle)

                toggle(
                    title: "Landscape layout",
                    explainer: "On = 4×2 rotated. Off = 2×4 upright portrait.",
                    isOn: Binding(
                        get: { model.isLandscapeLayout },
                        set: { model.setLandscapeLayout($0) }
                    )
                )
            }
        }
    }

    private var premiumCard: some View {
        VStack(alignment: .leading, spacing: DeckSpace.s) {
            Text("Premium")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.ochre)

            Text(model.entitlement == .premium
                 ? "Active — 8 pages, the recents column, and themes."
                 : "8 pages instead of 2 · recents column · themes")
                .deckFont(.bodySmall)
                .foregroundStyle(DeckColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.entitlement != .premium {
                Button { model.presentPaywall() } label: {
                    Text("Start free trial")
                        .deckFont(.legend)
                        .foregroundStyle(DeckColor.onOchre)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(DeckColor.ochre, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DeckSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    private var rowList: some View {
        card {
            VStack(spacing: 0) {
                row("Restore purchases") { Task { await model.entitlements.restore() } }
                Divider().overlay(DeckColor.strokeSubtle)
                row("Permissions", trailing: model.permissions.summary)
                Divider().overlay(DeckColor.strokeSubtle)
                row("About & privacy", trailing: "No account · no cloud")
            }
        }
    }

    // MARK: - Pieces

    private var connectionSummary: String {
        switch model.session.state {
        case .connected(let latencyMs):
            return latencyMs > 0 ? "● Connected · \(latencyMs)ms" : "● Connected"
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .disconnected: return "Disconnected"
        }
    }

    private func toggle(title: String, explainer: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: DeckSpace.xs) {
            Toggle(isOn: isOn) {
                Text(title)
                    .deckFont(.body)
                    .foregroundStyle(DeckColor.ink)
            }
            .tint(DeckColor.mint)

            Text(explainer)
                .deckFont(.bodySmall)
                .foregroundStyle(DeckColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ title: String, trailing: String? = nil, action: (() -> Void)? = nil) -> some View {
        Button { action?() } label: {
            HStack {
                Text(title)
                    .deckFont(.body)
                    .foregroundStyle(DeckColor.ink)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .deckFont(.bodySmall)
                        .foregroundStyle(DeckColor.inkMuted)
                }
                if action != nil {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(DeckColor.inkFaint)
                }
            }
            .frame(minHeight: 46)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(DeckSpace.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DeckColor.surface, in: RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DeckRadius.card, style: .continuous)
                    .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
            }
    }
}

enum AppInfo {
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
        let build = (info?["CFBundleVersion"] as? String) ?? "1"
        return "\(short) (\(build))"
    }
}
