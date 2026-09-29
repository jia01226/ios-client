import XCTest

final class ChatLineSwitcherTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOnlySwitchesBetweenTestWindows() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control"]
        app.launch()

        let testSwitcher = app.buttons["chat-line-switcher-test1"]
        XCTAssertTrue(testSwitcher.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["测试1 · 在线"].exists)
        testSwitcher.tap()
        XCTAssertFalse(app.buttons["原版"].exists)
        XCTAssertFalse(app.buttons["精简版"].exists)
        app.buttons["测试2"].tap()
        let test2Switcher = app.buttons["chat-line-switcher-test2"]
        XCTAssertTrue(test2Switcher.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["测试2 · 在线"].exists)
        test2Switcher.tap()
        XCTAssertFalse(app.buttons["原版"].exists)
        XCTAssertFalse(app.buttons["精简版"].exists)
        app.buttons["测试1"].tap()
        XCTAssertTrue(testSwitcher.waitForExistence(timeout: 5))
    }
}
