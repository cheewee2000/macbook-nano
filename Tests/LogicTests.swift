import XCTest
@testable import MacbookNano

final class LogicTests: XCTestCase {
    private func syms(_ e: [ModifierLatch.Event]) -> [String] { e.map { "\($0.sym == Sym.command ? "cmd" : "shift")\($0.down ? "+" : "-")" }.sorted() }

    func testTapLatchesForOneKey() {
        var m = ModifierLatch()
        XCTAssertEqual(syms(m.modifierDown(Sym.command)), ["cmd+"])
        XCTAssertEqual(syms(m.modifierUp(Sym.command)), [])            // tap: still held on the Mac
        m.keyDown()
        XCTAssertEqual(syms(m.keyUp()), ["cmd-"])                      // released after the next key
        XCTAssert(m.down.isEmpty)
    }

    func testHeldModifierSurvivesSeveralKeys() {                       // hold cmd, tab, tab
        var m = ModifierLatch()
        _ = m.modifierDown(Sym.command)
        m.keyDown(); XCTAssertEqual(syms(m.keyUp()), [])
        m.keyDown(); XCTAssertEqual(syms(m.keyUp()), [])
        XCTAssertEqual(syms(m.modifierUp(Sym.command)), ["cmd-"])
    }

    func testSecondTapUnlatches() {
        var m = ModifierLatch()
        _ = m.modifierDown(Sym.shift); _ = m.modifierUp(Sym.shift)
        XCTAssertEqual(syms(m.modifierDown(Sym.shift)), [])            // already down: no second key-down
        XCTAssertEqual(syms(m.modifierUp(Sym.shift)), ["shift-"])
    }

    func testTwoLatchedModifiersReleaseTogether() {                    // shift, cmd, 4
        var m = ModifierLatch()
        _ = m.modifierDown(Sym.shift); _ = m.modifierUp(Sym.shift)
        _ = m.modifierDown(Sym.command); _ = m.modifierUp(Sym.command)
        m.keyDown()
        XCTAssertEqual(syms(m.keyUp()), ["cmd-", "shift-"])
    }

    func testViewport() {
        let box = CGSize(width: 500, height: 350), mac = CGSize(width: 1920, height: 1080)
        // zoom 1: whole screen, letterboxed and centered
        let fit = viewport(container: box, screen: mac, zoom: 1, center: CGPoint(x: 960, y: 540))
        XCTAssertEqual(fit.width, 500, accuracy: 0.01)
        XCTAssertEqual(fit.midY, 175, accuracy: 0.01)
        XCTAssertEqual(viewport(container: box, screen: .zero, zoom: 1, center: .zero), .zero)
        // zoomed in: wherever the view is asked to go, it never shows past an edge
        let scale = 500.0 / 1920 * 4, visible = CGSize(width: 500 / scale, height: 350 / scale)
        for want in [CGPoint(x: -500, y: -500), CGPoint(x: 960, y: 540), CGPoint(x: 5000, y: 5000)] {
            let r = viewport(container: box, screen: mac, zoom: 4, center: clamped(center: want, screen: mac, visible: visible))
            XCTAssertLessThanOrEqual(r.minX, 0.01); XCTAssertGreaterThanOrEqual(r.maxX, 499.99)
            XCTAssertLessThanOrEqual(r.minY, 0.01); XCTAssertGreaterThanOrEqual(r.maxY, 349.99)
        }
    }

    func testViewFollowsThePointerOnlyAtItsEdges() {
        let visible = CGSize(width: 400, height: 200), c = CGPoint(x: 1000, y: 500)
        XCTAssertEqual(following(CGPoint(x: 1100, y: 550), center: c, visible: visible), c)             // inside: view holds still
        XCTAssertEqual(following(CGPoint(x: 1300, y: 500), center: c, visible: visible).x, 1140)        // pushed right
        XCTAssertEqual(following(CGPoint(x: 1000, y: 100), center: c, visible: visible).y, 180)         // pushed up
    }

    func testPinchKeepsThePixelUnderTheFingers() {
        let m = Mac()
        m.size = CGSize(width: 1920, height: 1080)
        m.viewSize = CGSize(width: 500, height: 350)
        m.pinch(by: 0.01, at: .zero)                             // whatever zoom the last run saved: back to 1
        m.pinch(by: 3, at: CGPoint(x: 250, y: 175))              // zoom in on the middle first, away from the edges
        let p = CGPoint(x: 310, y: 140)
        let under = { () -> CGPoint in let r = m.viewRect, k = r.width / 1920; return CGPoint(x: (p.x - r.minX) / k, y: (p.y - r.minY) / k) }
        let before = under()
        m.pinch(by: 1.5, at: p)
        XCTAssertEqual(m.zoom, 4.5, accuracy: 0.001)
        XCTAssertEqual(under().x, before.x, accuracy: 0.01); XCTAssertEqual(under().y, before.y, accuracy: 0.01)
        m.pan(by: CGPoint(x: 50, y: 0))                          // drag right: the picture moves right with the fingers
        XCTAssertEqual(under().x, before.x - 50 / (m.viewRect.width / 1920), accuracy: 0.01)
        m.pinch(by: 0.01, at: p)                                 // all the way out: never below the whole screen
        XCTAssertEqual(m.zoom, 1)
    }

    func testKeyRowsAreAllTheSameWidth() {
        let arrows: CGFloat = 3
        for (i, row) in keyRows.enumerated() {
            XCTAssertEqual(row.reduce(0) { $0 + $1.width } + (i == keyRows.count - 1 ? arrows : 0), 14.5, accuracy: 0.001)
        }
        let all = keyRows.flatMap { $0 } + [arrowKeys.left, arrowKeys.up, arrowKeys.down, arrowKeys.right]
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(all.count, 78)                                  // a US MacBook Pro has 78 keys
    }

    func testWhatAKeySends() {
        let key = { (id: String) in (keyRows.flatMap { $0 } + [arrowKeys.left]).first { $0.id == id }! }
        XCTAssertEqual(keysym(for: key("a"), modifiers: [], capsLock: false), 0x61)
        XCTAssertEqual(keysym(for: key("a"), modifiers: [Sym.shift], capsLock: false), 0x41)
        XCTAssertEqual(keysym(for: key("a"), modifiers: [], capsLock: true), 0x41)
        XCTAssertEqual(keysym(for: key("a"), modifiers: [Sym.shift], capsLock: true), 0x61)       // as on a Mac
        XCTAssertEqual(keysym(for: key("1"), modifiers: [], capsLock: true), 0x31)                // caps lock is letters only
        XCTAssertEqual(keysym(for: key("1"), modifiers: [Sym.shift], capsLock: false), 0x21)
        XCTAssertEqual(keysym(for: key("delete"), modifiers: [Sym.fn], capsLock: false), Sym.forwardDelete)
        XCTAssertEqual(keysym(for: key("left"), modifiers: [Sym.fn], capsLock: false), Sym.home)
        XCTAssertEqual(keysym(for: key("f5"), modifiers: [], capsLock: false), 0xffc2)
    }
}
