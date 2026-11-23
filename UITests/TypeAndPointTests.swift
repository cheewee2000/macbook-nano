import XCTest

/// End to end against test/fake_mac.py (start it first; test/run.sh does). The fake Mac logs what arrives,
/// run.sh checks the log: the keys typed here and a pointer that moved and clicked.
final class TypeAndPointTests: XCTestCase {
    func testTypeAndPoint() {
        let app = XCUIApplication()
        app.launchArguments = ["-host", "127.0.0.1:5999", "-user", "", "-zoom", "1"]
        app.launch()

        let a = app.buttons["key-a"]
        XCTAssert(a.waitForExistence(timeout: 20), "never connected to the fake Mac")
        a.tap()                                    // a
        app.buttons["key-shift"].tap()             // latched shift
        app.buttons["key-1"].tap()                 // !
        app.buttons["key-b"].tap()                 // shift let go: b, not B
        app.buttons["key-cmd"].tap()
        app.buttons["key-c"].tap()                 // cmd + c
        app.buttons["key-return"].tap()

        let pad = app.otherElements["trackpad"]
        let from = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7)))
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()   // click

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        sleep(1)                                   // let the last events reach the server
    }
}
