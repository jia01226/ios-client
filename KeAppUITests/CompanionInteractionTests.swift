import XCTest

final class CompanionInteractionTests: XCTestCase {
    func testCalendarPrivacyAndDailyPages() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-app.skin", "day"]
        app.launch()
        XCTAssertTrue(app.buttons["我们"].waitForExistence(timeout: 5))
        app.buttons["我们"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["日历"].waitForExistence(timeout: 5))
        app.buttons["日历"].tap()
        XCTAssertTrue(app.staticTexts["当天安排"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["匿名私密记录"].exists)
        capture("companion-calendar-private-collapsed")
        app.buttons["关闭"].tap()
        app.buttons["日记"].tap()
        XCTAssertTrue(app.staticTexts["匿名日记"].waitForExistence(timeout: 5))
        capture("companion-diary")
        app.buttons["关闭"].tap()
        app.buttons["朋友圈"].tap()
        XCTAssertTrue(app.staticTexts["今天的天空很好看。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["评论"].exists)
        capture("companion-moments")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
