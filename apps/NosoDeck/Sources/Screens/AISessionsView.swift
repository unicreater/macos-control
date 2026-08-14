import DeckKit
import SwiftUI

/// A dedicated page showing live AI/terminal sessions from Warp, Claude, and ChatGPT.
/// Each session gets its own tile showing status (busy/idle/done).
struct AISessionsView: View {
    let sessions: [AppSessionInfo]
    let iconProvider: (String) -> Image?
    let onActivate: (String, Int?) -> Void // (bundleID, windowID?)

    private var allSessions: [(info: AppSessionInfo, session: AppSession)] {
        sessions.flatMap { info in
            info.sessions.map { (info: info, session: $0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 14)

            if allSessions.isEmpty {
                emptyState
            } else {
                sessionGrid
            }

            Spacer(minLength: 0)
        }
        .padding(.top, DeckGrid.topPadding)
        .padding(.bottom, DeckGrid.bottomPadding)
        .padding(.horizontal, DeckSpace.safeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckColor.chassis)
    }

    private var header: some View {
        HStack {
            Circle()
                .fill(allSessions.contains { $0.session.status == .busy } ? DeckColor.mint : DeckColor.inkMuted)
                .frame(width: 9, height: 9)
            Text("AI SESSIONS")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.inkMuted)
            Spacer()
            Text("\(allSessions.count) active")
                .deckFont(.meta)
                .foregroundStyle(DeckColor.inkFaint)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DeckSpace.l) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(DeckColor.inkFaint)
            Text("No AI sessions detected")
                .deckFont(.body)
                .foregroundStyle(DeckColor.inkMuted)
            Text("Open Warp, Claude, or ChatGPT to see sessions here")
                .deckFont(.bodySmall)
                .foregroundStyle(DeckColor.inkFaint)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var sessionGrid: some View {
        let items = Array(allSessions.prefix(8))

        return VStack(spacing: DeckGrid.gutter) {
            ForEach(0..<DeckGrid.rows, id: \.self) { row in
                HStack(spacing: DeckGrid.gutter) {
                    ForEach(0..<DeckGrid.columns, id: \.self) { column in
                        let index = row * DeckGrid.columns + column
                        if index < items.count {
                            sessionTile(items[index].info, items[index].session)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func sessionTile(_ info: AppSessionInfo, _ session: AppSession) -> some View {
        Button {
            onActivate(info.bundleID, session.windowID)
        } label: {
            VStack(spacing: 4) {
                appIcon(for: info.bundleID)
                    .frame(width: 48, height: 48)

                Text(session.label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DeckColor.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textCase(.uppercase)

                HStack(spacing: 3) {
                    Circle()
                        .fill(statusColor(session.status))
                        .frame(width: 5, height: 5)
                    Text(statusLabel(session))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(statusColor(session.status))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0x1E1E1E), Color(hex: 0x161616)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(statusColor(session.status).opacity(0.3), lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                // Status LED
                ZStack {
                    Circle()
                        .fill(statusColor(session.status).opacity(0.2))
                        .frame(width: 14, height: 14)
                    Circle()
                        .fill(statusColor(session.status))
                        .frame(width: 6, height: 6)
                }
                .padding(4)
            }
        }
        .buttonStyle(TileButtonStyle())
    }

    @ViewBuilder
    private func appIcon(for bundleID: String) -> some View {
        if let icon = iconProvider(bundleID) {
            icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            // Fallback SF Symbols
            switch bundleID {
            case "dev.warp.Warp-Stable":
                Image(systemName: "terminal")
                    .font(.system(size: 24))
                    .foregroundStyle(DeckColor.ink)
            case "com.anthropic.claudefordesktop":
                Image(systemName: "brain")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(hex: 0xD4A574))
            case "com.openai.chat":
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(hex: 0x74AA9C))
            default:
                Image(systemName: "app")
                    .font(.system(size: 24))
                    .foregroundStyle(DeckColor.inkMuted)
            }
        }
    }

    private func statusColor(_ status: AppSession.Status) -> Color {
        switch status {
        case .busy: return DeckColor.mint
        case .idle: return DeckColor.inkMuted
        case .done: return DeckColor.ochre
        }
    }

    private func statusLabel(_ session: AppSession) -> String {
        switch session.status {
        case .busy:
            if let detail = session.detail {
                return detail.uppercased()
            }
            return "BUSY"
        case .idle: return "IDLE"
        case .done: return "DONE"
        }
    }

    private func cpuBar(_ percent: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(hex: 0x1E1E1E))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(DeckColor.mint.opacity(0.6))
                    .frame(width: geo.size.width * min(percent / 100, 1))
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 8)
    }
}
