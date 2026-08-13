import DeckKit
import SwiftUI

/// App Time Travel — a scrollable horizontal timeline of recently activated apps.
/// Replaces the static recents column with a more visual, interactive strip.
struct AppTimeline: View {
    let recents: [String]
    let iconProvider: (String) -> Image?
    let nameProvider: (String) -> String?
    let onActivate: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9))
                Text("RECENT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(DeckColor.inkFaint)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recents, id: \.self) { bundleID in
                        timelineCell(bundleID)
                    }
                }
            }
        }
    }

    private func timelineCell(_ bundleID: String) -> some View {
        Button { onActivate(bundleID) } label: {
            VStack(spacing: 3) {
                if let icon = iconProvider(bundleID) {
                    icon
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: 0x2A2A2A))
                        .frame(width: 36, height: 36)
                }

                if let name = nameProvider(bundleID) {
                    Text(name)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(DeckColor.inkMuted)
                        .lineLimit(1)
                        .frame(maxWidth: 44)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
