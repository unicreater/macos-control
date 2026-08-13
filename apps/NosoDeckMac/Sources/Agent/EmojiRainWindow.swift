import AppKit

/// Rains emoji across the Mac screen using lightweight CATextLayers.
/// One rain at a time via a simple queue; each rain is fully independent.
@MainActor
final class EmojiRainWindow {
    private var busy = false
    private var pending: [String] = []

    func rain(_ character: String) {
        pending.append(character)
        if !busy { drainNext() }
    }

    private func drainNext() {
        guard let character = pending.first else {
            busy = false
            return
        }
        pending.removeFirst()
        busy = true
        show(character)
    }

    private func show(_ character: String) {
        guard let screen = NSScreen.main else {
            busy = false
            drainNext()
            return
        }

        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.ignoresMouseEvents = true
        win.hasShadow = false

        let container = NSView(frame: win.contentView!.bounds)
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear
        win.contentView?.addSubview(container)

        let w = screen.frame.width
        let h = screen.frame.height
        let count = 20

        for _ in 0..<count {
            let size = CGFloat.random(in: 28...48)
            let x = CGFloat.random(in: 0...(w - size))
            let delay = Double.random(in: 0...0.4)
            let duration = Double.random(in: 1.2...2.0)
            let rotation = CGFloat.random(in: -0.5...0.5)

            let layer = CATextLayer()
            layer.string = character
            layer.fontSize = size
            layer.alignmentMode = .center
            layer.frame = CGRect(x: x, y: h + 50, width: size + 10, height: size + 10)
            layer.contentsScale = screen.backingScaleFactor
            container.layer?.addSublayer(layer)

            // Fall from above screen to below
            let fall = CABasicAnimation(keyPath: "position.y")
            fall.fromValue = h + 50 + size / 2
            fall.toValue = -size
            fall.duration = duration
            fall.beginTime = CACurrentMediaTime() + delay
            fall.timingFunction = CAMediaTimingFunction(name: .easeIn)
            fall.fillMode = .forwards
            fall.isRemovedOnCompletion = false

            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = -rotation
            spin.toValue = rotation
            spin.duration = duration
            spin.beginTime = CACurrentMediaTime() + delay
            spin.fillMode = .forwards
            spin.isRemovedOnCompletion = false

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1.0
            fade.toValue = 0.0
            fade.duration = duration * 0.3
            fade.beginTime = CACurrentMediaTime() + delay + duration * 0.7
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false

            layer.add(fall, forKey: "fall")
            layer.add(spin, forKey: "spin")
            layer.add(fade, forKey: "fade")
        }

        win.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            win.close()
            self?.busy = false
            self?.drainNext()
        }
    }
}
