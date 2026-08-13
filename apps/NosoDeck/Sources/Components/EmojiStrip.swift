import DeckKit
import SwiftUI

/// Customizable emoji strip with multiple pages.
/// Long-press an emoji to replace it. Swipe to see more pages.
struct EmojiStrip: View {
    static let defaultPages: [[String]] = [
        ["👍", "🎉", "🙏", "😂", "❤️", "🔥", "✅", "👀"],
        ["🚀", "💡", "⭐", "🎯", "💪", "🤔", "👏", "😍"],
    ]

    private static let storageKey = "com.noso.nosodeck.emojiPages"

    @State private var pages: [[String]]
    @State private var currentPage = 0
    @State private var editingIndex: (page: Int, index: Int)?
    @State private var emojiInput = ""

    var isEnabled: Bool
    var onSend: (String) -> Void

    init(isEnabled: Bool, onSend: @escaping (String) -> Void) {
        self.isEnabled = isEnabled
        self.onSend = onSend
        let saved = UserDefaults.standard.object(forKey: Self.storageKey) as? [[String]]
        _pages = State(initialValue: saved ?? Self.defaultPages)
    }

    var body: some View {
        HStack(spacing: 4) {
            // Page indicator dots (if multiple pages)
            if pages.count > 1 {
                VStack(spacing: 3) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage ? DeckColor.ink : Color(hex: 0x333333))
                            .frame(width: 4, height: 4)
                            .onTapGesture { currentPage = i }
                    }
                }
            }

            ForEach(Array(currentEmoji.enumerated()), id: \.offset) { index, character in
                Button { onSend(character) } label: {
                    Text(character)
                        .font(.system(size: 18))
                        .frame(width: 34, height: 30)
                        .background(DeckColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: DeckRadius.badge, style: .continuous)
                                .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send \(character)")
                .contextMenu {
                    Button("Replace emoji...") {
                        editingIndex = (currentPage, index)
                    }
                }
            }
        }
        .opacity(isEnabled ? 1 : 0.38)
        .disabled(!isEnabled)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.width < -20 && currentPage < pages.count - 1 {
                        currentPage += 1
                    } else if value.translation.width > 20 && currentPage > 0 {
                        currentPage -= 1
                    }
                }
        )
        .alert("Replace Emoji", isPresented: showingAlert) {
            TextField("Paste emoji", text: $emojiInput)
            Button("Replace") {
                if let editing = editingIndex, !emojiInput.isEmpty {
                    let char = String(emojiInput.prefix(1))
                    pages[editing.page][editing.index] = char
                    save()
                }
                emojiInput = ""
                editingIndex = nil
            }
            Button("Cancel", role: .cancel) {
                emojiInput = ""
                editingIndex = nil
            }
        } message: {
            Text("Paste or type a single emoji")
        }
    }

    private var currentEmoji: [String] {
        guard currentPage < pages.count else { return [] }
        return pages[currentPage]
    }

    private var showingAlert: Binding<Bool> {
        Binding(
            get: { editingIndex != nil },
            set: { if !$0 { editingIndex = nil } }
        )
    }

    private func save() {
        UserDefaults.standard.set(pages, forKey: Self.storageKey)
    }
}
