import XCTest

final class ChatLineSwitcherTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSwitchesBetweenMainAndCompactWindows() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control"]
        app.launch()

        let mainSwitcher = app.buttons["chat-line-switcher-main"]
        XCTAssertTrue(mainSwitcher.waitForExistence(timeout: 5))
        mainSwitcher.tap()
        app.buttons["精简版"].tap()

        let compactSwitcher = app.buttons["chat-line-switcher-compact"]
        XCTAssertTrue(compactSwitcher.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["精简版 · 在线"].exists)

        compactSwitcher.tap()
        app.buttons["测试1"].tap()
        let testSwitcher = app.buttons["chat-line-switcher-test1"]
        XCTAssertTrue(testSwitcher.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["测试1 · 在线"].exists)
        testSwitcher.tap()
        app.buttons["测试2"].tap()
        let test2Switcher = app.buttons["chat-line-switcher-test2"]
        XCTAssertTrue(test2Switcher.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["测试2 · 在线"].exists)
        test2Switcher.tap()
        app.buttons["原版"].tap()
        XCTAssertTrue(mainSwitcher.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["原版 · 在线"].exists)
    }
}
