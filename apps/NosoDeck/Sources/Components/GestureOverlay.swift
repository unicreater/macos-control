import DeckKit
import SwiftUI
import UIKit

/// Installs multi-finger gesture recognizers on the app's key window.
/// Works over tiles — 2+ finger gestures are intercepted while single taps pass through.
struct WindowGestureInstaller: UIViewRepresentable {
    let onAction: (ActionKind) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false

        // Delay to ensure the window exists
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let window = view.window else { return }
            context.coordinator.install(on: window, onAction: onAction)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onAction = onAction
    }

    func makeCoordinator() -> GestureCoordinator { GestureCoordinator() }
}

class GestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    var onAction: ((ActionKind) -> Void)?
    private var installed = false
    private weak var feedbackView: GestureFeedbackView?

    func install(on window: UIWindow, onAction: @escaping (ActionKind) -> Void) {
        guard !installed else { return }
        installed = true
        self.onAction = onAction

        // Add a transparent feedback view to the window
        let feedback = GestureFeedbackView(frame: window.bounds)
        feedback.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        feedback.isUserInteractionEnabled = false
        window.addSubview(feedback)
        self.feedbackView = feedback

        var ourGestures: [UIGestureRecognizer] = []

        // 2-finger swipe in all 4 directions
        for direction: UISwipeGestureRecognizer.Direction in [.up, .down, .left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = direction
            swipe.numberOfTouchesRequired = 2
            swipe.delegate = self
            window.addGestureRecognizer(swipe)
            ourGestures.append(swipe)
        }

        // 2-finger double-tap (copy)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        doubleTap.numberOfTouchesRequired = 2
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        window.addGestureRecognizer(doubleTap)
        ourGestures.append(doubleTap)

        // 2-finger long-press (paste)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.numberOfTouchesRequired = 2
        longPress.minimumPressDuration = 0.5
        longPress.delegate = self
        window.addGestureRecognizer(longPress)
        ourGestures.append(longPress)

        // Find ALL UIScrollViews in the window and make their pan gestures
        // yield to our 2-finger gestures. This prevents TabView page scrolling
        // from eating multi-finger swipes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Self.configureScrollViews(in: window, toYieldTo: ourGestures)
        }
    }

    /// Recursively finds UIScrollViews and makes their pan gesture require
    /// our gesture recognizers to fail first.
    private static func configureScrollViews(in view: UIView, toYieldTo gestures: [UIGestureRecognizer]) {
        if let scrollView = view as? UIScrollView {
            for gesture in gestures {
                scrollView.panGestureRecognizer.require(toFail: gesture)
            }
        }
        for subview in view.subviews {
            configureScrollViews(in: subview, toYieldTo: gestures)
        }
    }

    @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        switch gesture.direction {
        case .up:
            fire(.maximizeWindow, label: "MAXIMIZE", icon: "arrow.up.left.and.arrow.down.right")
        case .down:
            fire(.minimizeWindow, label: "MINIMIZE", icon: "arrow.down.right.and.arrow.up.left")
        case .left:
            fire(.copyClipboard, label: "COPY", icon: "doc.on.doc")
        case .right:
            fire(.pasteClipboard, label: "PASTE", icon: "doc.on.clipboard")
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Allow our gestures to work alongside other recognizers
        true
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        // 2-finger double-tap = copy
        fire(.copyClipboard, label: "COPY", icon: "doc.on.doc")
    }

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        // 2-finger long-press = paste
        fire(.pasteClipboard, label: "PASTE", icon: "doc.on.clipboard")
    }

    private func fire(_ action: ActionKind, label: String, icon: String) {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        onAction?(action)
        feedbackView?.show(label: label, icon: icon)
    }
}

/// Transparent view that shows gesture feedback badges.
class GestureFeedbackView: UIView {
    private var badgeView: UIView?

    func show(label: String, icon: String) {
        badgeView?.removeFromSuperview()

        let badge = UIView()
        badge.backgroundColor = UIColor(white: 0.1, alpha: 0.95)
        badge.layer.cornerRadius = 20
        badge.layer.borderWidth = 1
        badge.layer.borderColor = UIColor(red: 0.64, green: 0.83, blue: 0.77, alpha: 0.3).cgColor

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = UIColor(red: 0.64, green: 0.83, blue: 0.77, alpha: 1)
        iconView.contentMode = .scaleAspectFit
        iconView.widthAnchor.constraint(equalToConstant: 20).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let textLabel = UILabel()
        textLabel.text = label
        textLabel.font = .monospacedSystemFont(ofSize: 14, weight: .bold)
        textLabel.textColor = UIColor(red: 0.64, green: 0.83, blue: 0.77, alpha: 1)

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(textLabel)
        badge.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: badge.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -10),
        ])

        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        badge.alpha = 0
        badge.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.15) {
            badge.alpha = 1
            badge.transform = .identity
        }

        self.badgeView = badge

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            UIView.animate(withDuration: 0.2, animations: {
                badge.alpha = 0
                badge.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            }) { _ in
                badge.removeFromSuperview()
                if self?.badgeView === badge { self?.badgeView = nil }
            }
        }
    }
}
