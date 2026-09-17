import XCTest

final class TimeSpaceInteractionTests: XCTestCase {
    func testTimeTabsOpenSharedCalendarAndKeepPrivateRecordsCollapsed() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-app.skin", "day"]
        app.launch()
        XCTAssertTrue(app.buttons["我们"].waitForExistence(timeout: 5))
        app.buttons["我们"].tap()
        XCTAssertTrue(app.buttons["time-anniversary-tab"].waitForExistence(timeout: 5))
        capture("us-time-reminders")
        app.buttons["time-anniversary-tab"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["us-moon-orbit-selector"].waitForExistence(timeout: 5))
        capture("us-time-anniversaries")
        app.buttons["time-reminder-tab"].tap()
        app.buttons["open-calendar"].tap()
        XCTAssertTrue(app.buttons["回到上面"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["calendar-month"].waitForExistence(timeout: 5))
        app.buttons["下个月"].tap()
        app.buttons["上个月"].tap()
        XCTAssertFalse(app.staticTexts["匿名私密记录"].exists)
        capture("us-time-calendar")
        app.buttons["day-9"].tap()
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["shift-option-早班"].exists)
        XCTAssertTrue(app.buttons["shift-option-上夜"].exists)
        XCTAssertTrue(app.buttons["shift-option-下夜"].exists)
        XCTAssertTrue(app.buttons["shift-option-早班+睡班"].exists)
        capture("us-time-shift-sheet")
        app.buttons["取消"].tap()
    }
    func testHorizontalSwipeSwitchesReminderAndAnniversaryPages() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-app.skin", "day"]
        app.launch()
        XCTAssertTrue(app.buttons["我们"].waitForExistence(timeout: 5))
        app.buttons["我们"].tap()
        XCTAssertTrue(app.buttons["time-anniversary-tab"].waitForExistence(timeout: 5))
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.40))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.40))
        right.press(forDuration: 0.05, thenDragTo: left, withVelocity: .slow, thenHoldForDuration: 0)
        let anniversary = app.staticTexts["把重要的日子留在这里"]
        XCTAssertTrue(anniversary.waitForExistence(timeout: 3))
        XCTAssertTrue(anniversary.isHittable)
        left.press(forDuration: 0.05, thenDragTo: right, withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons["open-calendar"].isHittable)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
