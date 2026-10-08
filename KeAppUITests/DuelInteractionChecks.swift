import XCTest

enum DuelInteractionChecks {
    static func verify(in testCase: XCTestCase, app: XCUIApplication) {
        app.buttons["play-duel"].tap()
        XCTAssertTrue(app.staticTexts["duel-unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["你和柯的牌桌已经摆好。"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "duel-network-failure-retry-and-close"; shot.lifetime = .keepAlways; testCase.add(shot)
        app.buttons["duel-retry"].tap()
        XCTAssertTrue(app.staticTexts["duel-unavailable"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["duel-close"].isHittable)
        app.buttons["duel-close"].tap()
        XCTAssertTrue(app.buttons["play-duel"].waitForExistence(timeout: 5))
    }
}
