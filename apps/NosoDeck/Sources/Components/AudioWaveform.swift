import SwiftUI

/// 40-bar audio waveform visualizer that reacts to live audio levels.
struct AudioWaveform: View {
    let levels: [CGFloat] // 0...1 for each bar
    let isRecording: Bool

    private let barCount = 40
    private let barWidth: CGFloat = 4
    private let barGap: CGFloat = 3
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 50
    private let cornerRadius: CGFloat = 2

    var body: some View {
        HStack(alignment: .center, spacing: barGap) {
            ForEach(0..<barCount, id: \.self) { i in
                let level = i < levels.count ? levels[i] : 0
                let height = minHeight + (maxHeight - minHeight) * level

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(barColor(level: level))
                    .frame(width: barWidth, height: height)
                    .animation(.linear(duration: 0.08), value: level)
            }
        }
        .frame(height: maxHeight)
    }

    private func barColor(level: CGFloat) -> Color {
        if !isRecording {
            return Color(hex: 0x3A3A3A)
        }
        // Top 10% of bars are brighter red
        if level > 0.7 {
            return DeckColor.red
        }
        return DeckColor.red.opacity(0.75)
    }
}
