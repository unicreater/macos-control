import DeckKit
import SwiftUI

/// A compact sheet for editing a tile's label and emoji.
struct EditTileSheet: View {
    let tile: Tile
    let onSave: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var emoji: String

    init(tile: Tile, onSave: @escaping (String, String?) -> Void) {
        self.tile = tile
        self.onSave = onSave
        _label = State(initialValue: tile.label)
        _emoji = State(initialValue: tile.emoji ?? "")
    }

    private var isAppTile: Bool { tile.kind == .app }

    var body: some View {
        VStack(alignment: .leading, spacing: DeckSpace.l) {
            // Header
            HStack {
                Text("Edit Tile")
                    .deckFont(.title)
                    .foregroundStyle(DeckColor.ink)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DeckColor.inkMuted)
                        .frame(width: 32, height: 32)
                        .background(DeckColor.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
            }

            // Label
            VStack(alignment: .leading, spacing: DeckSpace.s) {
                Text("Label")
                    .deckFont(.meta)
                    .foregroundStyle(DeckColor.inkMuted)
                TextField("Label", text: $label)
                    .textFieldStyle(.plain)
                    .deckFont(.body)
                    .foregroundStyle(DeckColor.ink)
                    .padding(.horizontal, DeckSpace.m)
                    .frame(height: 44)
                    .background(Color(hex: 0x141414), in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                            .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
                    }
            }

            // Emoji (not for app tiles — they use the real icon)
            if !isAppTile {
                VStack(alignment: .leading, spacing: DeckSpace.s) {
                    Text("Emoji")
                        .deckFont(.meta)
                        .foregroundStyle(DeckColor.inkMuted)
                    TextField("⚡️", text: $emoji)
                        .textFieldStyle(.plain)
                        .font(.system(size: 28))
                        .foregroundStyle(DeckColor.ink)
                        .multilineTextAlignment(.center)
                        .frame(width: 64, height: 48)
                        .background(Color(hex: 0x141414), in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                                .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
                        }
                        .onChange(of: emoji) { _, new in
                            emoji = String(new.prefix(1))
                        }
                }
            }

            // Info
            HStack(spacing: DeckSpace.s) {
                Image(systemName: tileIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(DeckColor.inkFaint)
                Text(tileDetail)
                    .deckFont(.meta)
                    .foregroundStyle(DeckColor.inkFaint)
            }

            Spacer()

            // Save
            Button {
                let trimmed = label.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                onSave(trimmed, isAppTile ? tile.emoji : (emoji.isEmpty ? nil : emoji))
                dismiss()
            } label: {
                Text("Save")
                    .deckFont(.body)
                    .foregroundStyle(DeckColor.onMint)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(DeckColor.mint, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(label.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
        .padding(DeckSpace.xl)
        .background(DeckColor.chassis)
        .preferredColorScheme(.dark)
    }

    private var tileIcon: String {
        switch tile.kind {
        case .app: return "app"
        case .shortcut: return "bolt"
        case .website: return "globe"
        case .keyCombo: return "command"
        case .folder: return "folder"
        }
    }

    private var tileDetail: String {
        switch tile.target {
        case .app(let bundleID): return bundleID
        case .shortcut(let name): return name
        case .website(let url): return url
        case .keyCombo(let combo): return combo.uppercased()
        case .folder(let id): return "Folder \(id.prefix(8))"
        }
    }
}
