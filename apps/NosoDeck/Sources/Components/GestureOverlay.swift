import DeckKit
import SwiftUI
import UIKit

/// Detects multi-finger swipe gestures over the deck using UIGestureRecognizers.
/// Single-finger taps pass through to the tiles below.
struct GestureOverlay: UIViewRepresentable {
    let onAction: (ActionKind) -> Void
    let onFeedback: (String, String) -> Void

    func makeUIView(context: Context) -> PassthroughView {
        let view = PassthroughView()
        view.backgroundColor = .clear

        // 2-finger swipe up (maximize)
        let swipeUp = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        swipeUp.direction = .up
        swipeUp.numberOfTouchesRequired = 2
        view.addGestureRecognizer(swipeUp)

        // 2-finger swipe down (minimize)
        let swipeDown = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        swipeDown.direction = .down
        swipeDown.numberOfTouchesRequired = 2
        view.addGestureRecognizer(swipeDown)

        // 4-finger swipe left (copy)
        let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        swipeLeft.direction = .left
        swipeLeft.numberOfTouchesRequired = 4
        view.addGestureRecognizer(swipeLeft)

        // 4-finger swipe right (paste)
        let swipeRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        swipeRight.direction = .right
        swipeRight.numberOfTouchesRequired = 4
        view.addGestureRecognizer(swipeRight)

        return view
    }

    func updateUIView(_ uiView: PassthroughView, context: Context) {
        context.coordinator.onAction = onAction
        context.coordinator.onFeedback = onFeedback
    }

    func makeCoordinator() -> Coordinator { Coordinator(onAction: onAction, onFeedback: onFeedback) }

    class Coordinator: NSObject {
        var onAction: (ActionKind) -> Void
        var onFeedback: (String, String) -> Void

        init(onAction: @escaping (ActionKind) -> Void, onFeedback: @escaping (String, String) -> Void) {
            self.onAction = onAction
            self.onFeedback = onFeedback
        }

        @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            let fingers = gesture.numberOfTouchesRequired
            switch (fingers, gesture.direction) {
            case (2, .up):
                onFeedback("Maximize", "arrow.up.left.and.arrow.down.right")
                onAction(.maximizeWindow)
            case (2, .down):
                onFeedback("Minimize", "arrow.down.right.and.arrow.up.left")
                onAction(.minimizeWindow)
            case (_, .left) where fingers >= 4:
                onFeedback("Copy", "doc.on.doc")
                onAction(.copyClipboard)
            case (_, .right) where fingers >= 4:
                onFeedback("Paste", "doc.on.clipboard")
                onAction(.pasteClipboard)
            default:
                break
            }
        }
    }
}

/// A UIView that passes through all single-finger touches to views below.
/// Only multi-finger gesture recognizers attached to it will activate.
final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Always return nil so touches pass through to SwiftUI views below.
        // The gesture recognizers still fire because they're attached to this view.
        return nil
    }
}
