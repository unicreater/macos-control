import DeckKit
import SwiftUI
import UIKit

/// Detects multi-finger swipe gestures over the deck.
/// - 2-finger swipe up → maximize window
/// - 2-finger swipe down → minimize window
/// - 4-finger swipe left → copy
/// - 4-finger swipe right → paste
struct GestureOverlay: UIViewRepresentable {
    let onAction: (ActionKind) -> Void
    let onFeedback: (String, String) -> Void // (label, SF Symbol)

    func makeUIView(context: Context) -> GestureView {
        let view = GestureView()
        view.onAction = onAction
        view.onFeedback = onFeedback
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ uiView: GestureView, context: Context) {
        uiView.onAction = onAction
        uiView.onFeedback = onFeedback
    }
}

final class GestureView: UIView {
    var onAction: ((ActionKind) -> Void)?
    var onFeedback: ((String, String) -> Void)?

    private var startPoints: [UITouch: CGPoint] = [:]

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            startPoints[touch] = touch.location(in: self)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let fingerCount = startPoints.count

        // Calculate average movement
        var totalDX: CGFloat = 0
        var totalDY: CGFloat = 0
        var count: CGFloat = 0

        for touch in touches {
            guard let start = startPoints[touch] else { continue }
            let end = touch.location(in: self)
            totalDX += end.x - start.x
            totalDY += end.y - start.y
            count += 1
        }

        guard count > 0 else {
            startPoints.removeAll()
            return
        }

        let avgDX = totalDX / count
        let avgDY = totalDY / count
        let threshold: CGFloat = 50

        if fingerCount == 2 {
            // 2-finger: vertical only
            if abs(avgDY) > threshold && abs(avgDY) > abs(avgDX) * 1.3 {
                if avgDY < 0 {
                    onFeedback?("Maximize", "arrow.up.left.and.arrow.down.right")
                    onAction?(.maximizeWindow)
                } else {
                    onFeedback?("Minimize", "arrow.down.right.and.arrow.up.left")
                    onAction?(.minimizeWindow)
                }
            }
        } else if fingerCount >= 4 {
            // 4-finger: horizontal only
            if abs(avgDX) > threshold && abs(avgDX) > abs(avgDY) * 1.3 {
                if avgDX < 0 {
                    onFeedback?("Copy", "doc.on.doc")
                    onAction?(.copyClipboard)
                } else {
                    onFeedback?("Paste", "doc.on.clipboard")
                    onAction?(.pasteClipboard)
                }
            }
        }

        startPoints.removeAll()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        startPoints.removeAll()
    }
}
