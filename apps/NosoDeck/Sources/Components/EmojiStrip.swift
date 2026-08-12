import DeckKit
import SwiftUI

/// The emoji strip (FR-15).
///
/// Tapping one sends it to the Mac, which types it if the user granted Accessibility
/// and puts it on the clipboard with a notification if they did not. The phone doesn't
/// need to know which happened — both are success, which is what "a real degraded path"
/// means in practice.
struct EmojiStrip: View {
    /// A small, deliberately unfashionable set: the ones people actually send.
    static let defaults = ["👍", "🎉", "🙏", "😂", "❤️", "🔥", "✅", "👀"]

    var emoji: [String] = EmojiStrip.defaults
    var isEnabled: Bool
    var onSend: (String) -> Void

    var body: some View {
        HStack(spacing: DeckSpace.s) {
            ForEach(emoji, id: \.self) { character in
                Button { onSend(character) } label: {
                    Text(character)
                        .font(.system(size: 20))
                        .frame(width: 38, height: 34)
                        .background(DeckColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous)
                                .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send \(character)")
            }
        }
        .opacity(isEnabled ? 1 : 0.38)
        .disabled(!isEnabled)
    }
}
