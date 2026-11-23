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
        let fit = viewport(container: box, screen: mac, zoom: 1, cursor: .zero)
        XCTAssertEqual(fit.width, 500, accuracy: 0.01)
        XCTAssertEqual(fit.midY, 175, accuracy: 0.01)
        // zoomed in: never shows past an edge, and the pointer is always inside the box
        for c in [CGPoint.zero, CGPoint(x: 960, y: 540), CGPoint(x: 1919, y: 1079)] {
            let r = viewport(container: box, screen: mac, zoom: 4, cursor: c)
            XCTAssertLessThanOrEqual(r.minX, 0); XCTAssertGreaterThanOrEqual(r.maxX, 500)
            let s = r.width / 1920, p = CGPoint(x: r.minX + c.x * s, y: r.minY + c.y * s)
            XCTAssert(CGRect(origin: .zero, size: box).insetBy(dx: -1, dy: -1).contains(p), "\(p)")
        }
        XCTAssertEqual(viewport(container: box, screen: .zero, zoom: 1, cursor: .zero), .zero)
    }

    func testKeyRowsAreAllTheSameWidth() {
        for row in keyRows { XCTAssertEqual(row.reduce(0) { $0 + $1.width }, 14.5, accuracy: 0.001) }
        XCTAssertEqual(Set(keyRows.flatMap { $0 }.map(\.id)).count, keyRows.flatMap { $0 }.count)
    }
}
