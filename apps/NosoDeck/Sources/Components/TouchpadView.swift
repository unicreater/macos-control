import DeckKit
import SwiftUI

/// A virtual trackpad — 1 finger moves cursor, tap clicks, 2 fingers scroll, pinch zooms.
/// Uses UIKit gesture recognizers for proper multi-touch detection.
struct TouchpadView: UIViewRepresentable {
    let onAction: (ActionKind, String) -> Void

    func makeUIView(context: Context) -> TouchpadUIView {
        let view = TouchpadUIView()
        view.onAction = onAction
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: TouchpadUIView, context: Context) {
        uiView.onAction = onAction
    }
}

class TouchpadUIView: UIView {
    var onAction: ((ActionKind, String) -> Void)?

    private let sensitivity: CGFloat = 2.5
    private let scrollSensitivity: CGFloat = 3.0
    private var lastMoveLocation: CGPoint = .zero
    private var lastScrollLocation: CGPoint = .zero
    private var isDragging = false

    private lazy var backgroundLayer: CALayer = {
        let l = CALayer()
        l.cornerRadius = 16
        l.borderWidth = 1
        l.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        return l
    }()

    private lazy var hintLabel: UILabel = {
        let l = UILabel()
        l.text = "Trackpad"
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = .white.withAlphaComponent(0.15)
        l.textAlignment = .center
        return l
    }()

    private lazy var hintIcon: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 28)
        let img = UIImage(systemName: "hand.point.up.left.and.text", withConfiguration: config)
        let iv = UIImageView(image: img)
        iv.tintColor = .white.withAlphaComponent(0.15)
        iv.contentMode = .center
        return iv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Visual effect background
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blur.layer.cornerRadius = 16
        blur.clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Border overlay
        layer.addSublayer(backgroundLayer)

        // Hint
        let stack = UIStackView(arrangedSubviews: [hintIcon, hintLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // 1 finger pan → move cursor
        let movePan = UIPanGestureRecognizer(target: self, action: #selector(handleMove(_:)))
        movePan.maximumNumberOfTouches = 1
        movePan.minimumNumberOfTouches = 1
        addGestureRecognizer(movePan)

        // 2 finger pan → scroll
        let scrollPan = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scrollPan.minimumNumberOfTouches = 2
        scrollPan.maximumNumberOfTouches = 2
        addGestureRecognizer(scrollPan)

        // Tap → click (Mac tracks timing for double/triple click)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.numberOfTouchesRequired = 1
        tap.delaysTouchesEnded = false
        addGestureRecognizer(tap)

        // Pinch → zoom
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)

    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundLayer.frame = bounds
    }

    @objc private func handleMove(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            isDragging = true
            lastMoveLocation = gesture.location(in: self)
            updateBorder(active: true)
        case .changed:
            let current = gesture.location(in: self)
            let dx = (current.x - lastMoveLocation.x) * sensitivity
            let dy = (current.y - lastMoveLocation.y) * sensitivity
            lastMoveLocation = current
            onAction?(.moveMouse, "\(dx),\(dy)")
        case .ended, .cancelled:
            isDragging = false
            updateBorder(active: false)
        default: break
        }
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            lastScrollLocation = gesture.location(in: self)
        case .changed:
            let current = gesture.location(in: self)
            let dy = (current.y - lastScrollLocation.y) * scrollSensitivity
            lastScrollLocation = current
            // Negative because natural scrolling: swipe up = scroll down
            onAction?(.scrollMouse, "\(-dy)")
        case .ended, .cancelled:
            break
        default: break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onAction?(.mouseClick, "1")
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .changed {
            let scale = gesture.scale - 1.0
            onAction?(.pinchZoom, "\(scale)")
            gesture.scale = 1.0
        }
    }


    private func updateBorder(active: Bool) {
        backgroundLayer.borderColor = UIColor.white.withAlphaComponent(active ? 0.25 : 0.1).cgColor
    }
}

/// The combined control panel: action buttons (left) + touchpad (right).
struct ControlPanelView: View {
    let model: AppModel
    let isLandscape: Bool
    var skipRotation: Bool = false
    let onDismiss: () -> Void

    private static let desktopActions: [ControlAction] = [
        ControlAction(icon: "chevron.left.2", label: "Space L", kind: .keyCombo, target: "ctrl+left"),
        ControlAction(icon: "chevron.right.2", label: "Space R", kind: .keyCombo, target: "ctrl+right"),
        ControlAction(icon: "rectangle.3.group", label: "Mission", kind: .keyCombo, target: "ctrl+up"),
        ControlAction(icon: "menubar.dock.rectangle", label: "Desktop", kind: .keyCombo, target: "cmd+f3"),
    ]

    private var allActions: [ControlAction] {
        let category = AppCategory.from(bundleID: model.macState.frontmost ?? "")
        let appActions = category.actions.map { ControlAction(icon: $0.icon, label: $0.label, kind: $0.action, target: "") }
        return appActions + Self.desktopActions
    }

    @State private var actionPage = 0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            GeometryReader { geo in
                let portraitW = geo.size.width
                let portraitH = geo.size.height
                // When skipRotation, the parent already provides landscape dimensions
                let contentW = isLandscape && !skipRotation ? portraitH : portraitW
                let contentH = isLandscape && !skipRotation ? portraitW : portraitH

                Group {
                    if isLandscape {
                        HStack(spacing: DeckSpace.s) {
                            pagedActionGrid(width: contentW * 0.4, height: contentH)
                                .frame(maxWidth: contentW * 0.4)
                            TouchpadView { kind, target in
                                model.sendAction(kind: kind, target: target)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .padding(DeckSpace.m)
                        .frame(width: contentW, height: contentH)
                    } else {
                        VStack(spacing: DeckSpace.s) {
                            actionGrid
                                .frame(maxHeight: contentH * 0.35)
                            TouchpadView { kind, target in
                                model.sendAction(kind: kind, target: target)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .padding(DeckSpace.m)
                        .frame(width: contentW, height: contentH)
                    }
                }
                .if(isLandscape && !skipRotation) { view in
                    view
                        .rotationEffect(.degrees(-90))
                        .frame(width: portraitW, height: portraitH)
                }
            }
        }
    }

    private var cols: [GridItem] {
        let count = isLandscape ? 3 : 3
        return Array(repeating: GridItem(.flexible(), spacing: DeckSpace.s), count: count)
    }

    // Portrait: scrollable grid of all actions
    private var actionGrid: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: DeckSpace.s) {
                ForEach(allActions) { item in
                    controlButton(item)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // Landscape: paginated — 3 cols, fit rows to available height
    private func pagedActionGrid(width: CGFloat, height: CGFloat) -> some View {
        let colCount = 3
        let rowHeight: CGFloat = 64
        let spacing = DeckSpace.s
        let availableH = height - DeckSpace.m * 2 - 20 // padding + page dots
        let rowsPerPage = max(Int(availableH / (rowHeight + spacing)), 1)
        let perPage = rowsPerPage * colCount
        let items = allActions
        let pageCount = max((items.count + perPage - 1) / perPage, 1)

        return VStack(spacing: 4) {
            TabView(selection: $actionPage) {
                ForEach(0..<pageCount, id: \.self) { page in
                    let start = page * perPage
                    let end = min(start + perPage, items.count)
                    let pageItems = Array(items[start..<end])
                    let pageCols = Array(repeating: GridItem(.flexible(), spacing: DeckSpace.s), count: colCount)

                    LazyVGrid(columns: pageCols, spacing: DeckSpace.s) {
                        ForEach(pageItems) { item in
                            controlButton(item)
                        }
                    }
                    .padding(.horizontal, 4)
                    .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: pageCount > 1 ? .automatic : .never))

            if pageCount > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Circle()
                            .fill(i == actionPage ? DeckColor.mint : Color.white.opacity(0.2))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
    }

    private func controlButton(_ item: ControlAction) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            model.sendAction(kind: item.kind, target: item.target)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(DeckColor.ink)
                Text(item.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DeckColor.inkMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(TileButtonStyle())
    }
}

private struct ControlAction: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let kind: ActionKind
    let target: String
}

private extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}
