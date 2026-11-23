import SwiftUI

/// Pointer speed. 1 = a slow swipe across the pad covers about half the Mac's screen. Tune on the real device.
let pointerSpeed: CGFloat = 1
/// Two-finger travel per wheel click, in points.
let scrollStep: CGFloat = 12

/// Trackpad points → framebuffer px: slow is precise, a flick is up to 3× faster, zooming in slows it down.
func pointerGain(speed: CGFloat, screenWidth: CGFloat, zoom: CGFloat) -> CGFloat {
    pointerSpeed * min(max(speed / 400, 1), 3) * screenWidth / 1000 / max(zoom, 1).squareRoot()
}

/// One finger moves, tap clicks, two-finger tap right-clicks, two fingers scroll (natural),
/// hold a moment then move to drag.
struct Trackpad: UIViewRepresentable {
    let mac: Mac

    func makeCoordinator() -> Pad { Pad(mac) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(), c = context.coordinator
        v.isMultipleTouchEnabled = true
        v.accessibilityIdentifier = "trackpad"
        let move = UIPanGestureRecognizer(target: c, action: #selector(Pad.move))
        move.maximumNumberOfTouches = 1
        let scroll = UIPanGestureRecognizer(target: c, action: #selector(Pad.scroll))
        scroll.minimumNumberOfTouches = 2
        let tap = UITapGestureRecognizer(target: c, action: #selector(Pad.tap))
        let tap2 = UITapGestureRecognizer(target: c, action: #selector(Pad.tap2))
        tap2.numberOfTouchesRequired = 2
        let hold = UILongPressGestureRecognizer(target: c, action: #selector(Pad.hold))
        hold.minimumPressDuration = 0.25
        tap.require(toFail: hold)
        for g in [move, scroll, tap, tap2, hold] { g.delegate = c; v.addGestureRecognizer(g) }
        return v
    }

    func updateUIView(_ v: UIView, context: Context) {}

    final class Pad: NSObject, UIGestureRecognizerDelegate {
        let mac: Mac
        private var wheel = CGPoint.zero
        init(_ mac: Mac) { self.mac = mac }

        // hold + move = drag, so those two must run together
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

        @objc func move(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view), v = g.velocity(in: g.view)
            g.setTranslation(.zero, in: g.view)
            let zoom = UserDefaults.standard.object(forKey: "zoom") as? Double ?? 1
            let k = pointerGain(speed: hypot(v.x, v.y), screenWidth: mac.size.width, zoom: zoom)
            mac.move(by: CGSize(width: t.x * k, height: t.y * k))
        }

        @objc func scroll(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            g.setTranslation(.zero, in: g.view)
            wheel.x += t.x; wheel.y += t.y
            // natural scrolling: the content follows the fingers
            while abs(wheel.y) >= scrollStep { mac.scroll(wheel.y > 0 ? .up : .down); wheel.y -= wheel.y > 0 ? scrollStep : -scrollStep }
            while abs(wheel.x) >= scrollStep { mac.scroll(wheel.x > 0 ? .left : .right); wheel.x -= wheel.x > 0 ? scrollStep : -scrollStep }
            if g.state == .ended || g.state == .cancelled { wheel = .zero }
        }

        @objc func tap() { mac.click(.left) }
        @objc func tap2() { mac.click(.right) }

        @objc func hold(_ g: UILongPressGestureRecognizer) {
            if g.state == .began { mac.button(.left, down: true); UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            if g.state == .ended || g.state == .cancelled { mac.button(.left, down: false) }
        }
    }
}
