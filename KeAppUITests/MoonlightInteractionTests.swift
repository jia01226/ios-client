import XCTest

final class MoonlightInteractionTests: XCTestCase {
    func testFourTabsDiaryDateAndDrawerPrivacy() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-ui-test-moonlight", "-app.skin", "day"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-ke"].waitForExistence(timeout: 12))
        capture("01-chat")
        app.buttons["tab-us"].tap()
        XCTAssertTrue(app.buttons["notes-add"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["anniversary-together"].exists)
        capture("02-us")
        app.swipeUp()
        XCTAssertTrue(app.buttons["period-start"].waitForExistence(timeout: 5))
        capture("03-month-calendar")
        app.buttons["tab-play"].tap()
        XCTAssertTrue(app.buttons["play-tarot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["play-duel"].exists)
        XCTAssertFalse(app.buttons["play-hut"].exists)
        capture("04-play")
        app.buttons["tab-drawer"].tap()
        XCTAssertTrue(app.buttons["diary-open-close"].waitForExistence(timeout: 8))
        capture("05-diary-cover")
        app.buttons["diary-rail--1"].tap()
        app.buttons["diary-open-close"].tap()
        XCTAssertTrue(app.staticTexts["diary-page-content"].waitForExistence(timeout: 6))
        let before = app.staticTexts["diary-page-date"].label
        let page = app.otherElements["diary-paper-page"]
        if page.exists { page.swipeLeft() } else { app.swipeLeft() }
        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: app.staticTexts["diary-page-date"])
        waitForExpectations(timeout: 5)
        capture("06-diary-turned")
        app.buttons["diary-date-picker"].tap()
        XCTAssertTrue(app.buttons["diary-date-done"].waitForExistence(timeout: 5))
        capture("07-diary-date-picker")
        app.buttons["diary-date-done"].tap()
        app.buttons["ke-drawer-tab"].tap()
        XCTAssertTrue(app.buttons["drawer-pull"].waitForExistence(timeout: 8))
        capture("08-drawer-closed")
        app.buttons["drawer-pull"].tap()
        XCTAssertTrue(app.buttons["drawer-letter-501"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["PRIVATE_PAYLOAD_MUST_NOT_RENDER"].exists)
        XCTAssertFalse(app.staticTexts["不应显示的私密标题"].exists)
        capture("09-drawer-open")
        app.buttons["drawer-letter-501"].tap()
        XCTAssertTrue(app.staticTexts["慢慢来，我会陪着你。"].waitForExistence(timeout: 5))
        capture("10-drawer-letter")
    }
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
