import DeckKit
import SwiftUI

struct ClipboardHistoryView: View {
    let model: AppModel
    @State private var flippedID: UUID?
    @State private var swipeOffsets: [UUID: CGSize] = [:]

    private var isLandscape: Bool { model.isLandscapeLayout }

    private var unpinnedItems: [ClipboardItem] {
        model.clipboardHistory.filter { !model.isClipboardPinned($0.id) }
    }

    private var pinnedItems: [ClipboardItem] {
        model.clipboardHistory.filter { model.isClipboardPinned($0.id) }
    }

    var body: some View {
        GeometryReader { geo in
            let portraitW = geo.size.width
            let portraitH = geo.size.height
            let contentW = isLandscape ? portraitH : portraitW
            let contentH = isLandscape ? portraitW : portraitH
            let cardW = (isLandscape ? contentH : contentW) * 0.38
            let cardH = cardW * 1.1

            if model.clipboardHistory.isEmpty {
                VStack(spacing: DeckSpace.s) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("No clipboard history yet")
                        .deckFont(.bodySmall)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Copy something on your Mac")
                        .deckFont(.meta)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(width: contentW, height: contentH)
                .if(isLandscape) { view in
                    view
                        .rotationEffect(.degrees(LandscapeDirection.angle))
                        .frame(width: portraitW, height: portraitH)
                }
            } else {
                Group {
                    if isLandscape {
                        landscapeLayout(cardW: cardW, cardH: cardH, contentW: contentW, contentH: contentH)
                    } else {
                        portraitLayout(cardW: cardW, cardH: cardH, contentW: contentW, contentH: contentH)
                    }
                }
                .if(isLandscape) { view in
                    view
                        .rotationEffect(.degrees(LandscapeDirection.angle))
                        .frame(width: portraitW, height: portraitH)
                }
            }
        }
        .background(.clear)
    }

    // MARK: - Landscape: 60% unpinned | pill divider | 40% pinned

    private func landscapeLayout(cardW: CGFloat, cardH: CGFloat, contentW: CGFloat, contentH: CGFloat) -> some View {
        HStack(spacing: 0) {
            if pinnedItems.isEmpty {
                clipboardScroll(items: unpinnedItems, cardW: cardW, cardH: cardH, axis: .horizontal)
            } else {
                clipboardScroll(items: unpinnedItems, cardW: cardW, cardH: cardH, axis: .horizontal)
                    .frame(width: contentW * 0.58)

                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 5, height: cardH * 1.1)

                clipboardScroll(items: pinnedItems, cardW: cardW, cardH: cardH, axis: .horizontal, pinned: true)
                    .frame(width: contentW * 0.38)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(width: contentW, height: contentH)
    }

    // MARK: - Portrait: unpinned top | pill divider | pinned bottom

    private func portraitLayout(cardW: CGFloat, cardH: CGFloat, contentW: CGFloat, contentH: CGFloat) -> some View {
        VStack(spacing: 0) {
            if pinnedItems.isEmpty {
                clipboardScroll(items: unpinnedItems, cardW: cardW, cardH: cardH, axis: .vertical)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                clipboardScroll(items: unpinnedItems, cardW: cardW, cardH: cardH, axis: .vertical)
                    .frame(maxWidth: .infinity)
                    .frame(height: contentH * 0.56)

                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: cardW * 1.1, height: 5)

                clipboardScroll(items: pinnedItems, cardW: cardW * 0.85, cardH: cardH * 0.85, axis: .vertical, pinned: true)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: contentW, height: contentH)
    }

    // MARK: - Shared

    private func clipboardScroll(items: [ClipboardItem], cardW: CGFloat, cardH: CGFloat, axis: Axis.Set, pinned: Bool = false) -> some View {
        ZStack {
            if flippedID != nil {
                Color.black.opacity(0.001)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            flippedID = nil
                        }
                    }
            }

            ScrollView(axis, showsIndicators: false) {
                let layout = axis == .horizontal
                    ? AnyLayout(HStackLayout(spacing: -cardW * 0.2))
                    : AnyLayout(VStackLayout(spacing: -cardW * 0.2))

                layout {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        clipboardCard(item: item, cardW: cardW, cardH: cardH, isPinned: pinned)
                            .zIndex(flippedID == item.id ? 100 : Double(index))
                    }
                }
                .padding(axis == .horizontal ? .horizontal : .vertical, 30)
            }
            .scrollEdgeEffectHidden(true)
        }
    }

    private func clipboardCard(item: ClipboardItem, cardW: CGFloat, cardH: CGFloat, isPinned: Bool) -> some View {
        ClipboardCard(
            item: item,
            isFlipped: flippedID == item.id,
            isPinned: isPinned,
            width: cardW,
            height: cardH,
            onTap: {
                if flippedID == item.id {
                    model.pasteClipboardItem(item)
                    Haptics.tileTap()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        flippedID = nil
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        flippedID = item.id
                    }
                }
            }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.togglePinClipboard(item.id)
                }
            }
        )
        .offset(swipeOffsets[item.id] ?? .zero)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    // "Up" from the card's top depends on rotation:
                    // -90°: screen-right (positive x) = card-up
                    //  90°: screen-left (negative x) = card-up
                    //   0°: screen-up (negative y) = card-up
                    let angle = LandscapeDirection.angle
                    let dismiss: CGFloat
                    if angle == -90 {
                        dismiss = max(value.translation.width, 0) // right only
                    } else if angle == 90 {
                        dismiss = max(-value.translation.width, 0) // left only
                    } else {
                        dismiss = max(-value.translation.height, 0) // up only
                    }
                    let offset: CGSize
                    if angle == -90 {
                        offset = CGSize(width: max(value.translation.width, 0), height: 0)
                    } else if angle == 90 {
                        offset = CGSize(width: min(value.translation.width, 0), height: 0)
                    } else {
                        offset = CGSize(width: 0, height: min(value.translation.height, 0))
                    }
                    swipeOffsets[item.id] = dismiss > 0 ? offset : .zero
                }
                .onEnded { value in
                    let angle = LandscapeDirection.angle
                    let dismiss: CGFloat
                    if angle == -90 {
                        dismiss = value.translation.width
                    } else if angle == 90 {
                        dismiss = -value.translation.width
                    } else {
                        dismiss = -value.translation.height
                    }

                    if dismiss > 80 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        let flyOut: CGSize
                        if angle == -90 {
                            flyOut = CGSize(width: 500, height: 0)
                        } else if angle == 90 {
                            flyOut = CGSize(width: -500, height: 0)
                        } else {
                            flyOut = CGSize(width: 0, height: -500)
                        }
                        withAnimation(.easeOut(duration: 0.25)) {
                            swipeOffsets[item.id] = flyOut
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            swipeOffsets.removeValue(forKey: item.id)
                            model.removeClipboardItem(id: item.id)
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            swipeOffsets[item.id] = .zero
                        }
                    }
                }
        )
    }
}

// MARK: - Card

private struct ClipboardCard: View {
    let item: ClipboardItem
    let isFlipped: Bool
    let isPinned: Bool
    let width: CGFloat
    let height: CGFloat
    let onTap: () -> Void

    private var timeAgo: String {
        let seconds = Int(Date().timeIntervalSince(item.timestamp))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                frontCard
                    .opacity(isFlipped ? 0 : 1)
                    .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                backCard
                    .opacity(isFlipped ? 1 : 0)
                    .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
            }
            .frame(width: isFlipped ? width * 1.3 : width, height: isFlipped ? height * 1.2 : height)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isFlipped)
        }
        .buttonStyle(TileButtonStyle())
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        .overlay(alignment: .topTrailing) {
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
        }
    }

    private var frontCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DeckColor.ink)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                Text(timeAgo)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DeckColor.inkFaint)
                Spacer()
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 10))
                    .foregroundStyle(DeckColor.inkFaint)
            }
        }
        .padding(10)
        .frame(width: width, height: height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
    }

    private var backCard: some View {
        VStack(spacing: 8) {
            ScrollView {
                Text(item.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DeckColor.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 4) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 11))
                Text("Tap to paste")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(DeckColor.mint)
        }
        .padding(12)
        .frame(width: width * 1.3, height: height * 1.2)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(DeckColor.mint.opacity(0.3), lineWidth: 1)
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}
