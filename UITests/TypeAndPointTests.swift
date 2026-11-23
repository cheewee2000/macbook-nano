import XCTest

/// End to end against test/fake_mac.py (start it first; test/run.sh does). The fake Mac asks for a login the
/// way a real one does and logs what arrives; run.sh checks the log: the login, the keys typed here, and a
/// pointer that moved and clicked.
final class TypeAndPointTests: XCTestCase {
    func testTypeAndPoint() {
        let app = XCUIApplication()
        // A user name nobody has saved a password for: the launch connect is refused (as with a wrong password
        // on a real Mac), then the password is typed in and CONNECT pressed.
        app.launchArguments = ["-host", "127.0.0.1:5999", "-user", "tester\(Int.random(in: 0..<1_000_000))", "-zoom", "1"]
        app.launch()

        XCTAssert(app.staticTexts["ERROR"].waitForExistence(timeout: 20), "the refused login never showed an error")
        let password = app.secureTextFields["password"]
        password.tap()
        password.typeText("c0rrect horse!")
        app.buttons["CONNECT"].tap()

        let a = app.buttons["key-a"]
        XCTAssert(a.waitForExistence(timeout: 20), "never got in to the fake Mac")
        // the sign-in screen and the iOS keyboard are still animating away for a moment: taps before that go nowhere
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: a)], timeout: 10)
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
