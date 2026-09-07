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
        app.buttons["原版"].tap()
        XCTAssertTrue(mainSwitcher.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["原版 · 在线"].exists)
    }
}
