import AppKit
import Foundation

/// Detects when the user is dragging on the Mac (mouse button held while moving).
/// Reports changes so the phone can highlight tiles for drop-target switching.
@MainActor
final class DragDetector {
    var onChange: ((Bool) -> Void)?
    private var timer: DispatchSourceTimer?
    private(set) var isDragging = false

    func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.5, repeating: 0.3)
        t.setEventHandler { [weak self] in
            self?.poll()
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        // Check if the left mouse button is currently held down
        let buttons = NSEvent.pressedMouseButtons
        let leftDown = buttons & 1 != 0

        // Dragging = mouse button held and mouse has moved (we approximate by
        // checking if button has been held for at least one poll cycle)
        let wasDragging = isDragging
        isDragging = leftDown

        if isDragging != wasDragging {
            onChange?(isDragging)
        }
    }
}
