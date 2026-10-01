import XCTest

final class UsInteractionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAnniversaryPagerSwipesAndKeepsSelectionAcrossTabRoundTrip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control"]
        app.launch()

        let usTab = app.buttons["我们"]
        XCTAssertTrue(usTab.waitForExistence(timeout: 5))
        usTab.tap()

        let pager = app.descendants(matching: .any)["us-anniversary-pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["表白的日子"].exists)
        attachScreenshot(named: "20-us-default-anniversary")

        pager.swipeLeft()
        XCTAssertTrue(app.staticTexts["在一起的日子"].waitForExistence(timeout: 2))
        attachScreenshot(named: "21-us-next-anniversary")

        app.buttons["柯"].tap()
        XCTAssertTrue(app.buttons["我们"].waitForExistence(timeout: 2))
        app.buttons["我们"].tap()

        XCTAssertTrue(pager.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["在一起的日子"].exists)
        attachScreenshot(named: "23-us-tab-round-trip")
    }

    func testCalendarCanMoveToAnotherMonthAndReturn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-preview-us", "-preview-us-calendar"]
        app.launch()

        let nextMonth = app.buttons["下个月"]
        XCTAssertTrue(nextMonth.waitForExistence(timeout: 5))
        nextMonth.tap()
        XCTAssertTrue(app.buttons["calendar-return-current-month"].waitForExistence(timeout: 2))
        attachScreenshot(named: "22-us-next-month")
        app.buttons["calendar-return-current-month"].tap()
        XCTAssertFalse(app.buttons["calendar-return-current-month"].exists)
    }

    func testCalendarDayCanWriteShift() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-preview-us", "-preview-us-calendar"]
        app.launch()

        let day = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-day-'")).element(boundBy: 0)
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()

        XCTAssertTrue(app.staticTexts["写班表"].waitForExistence(timeout: 2))
        app.buttons["其他"].tap()
        let note = app.textFields["写下班次，例如：培训、临时班"]
        XCTAssertTrue(note.waitForExistence(timeout: 2))
        note.tap()
        note.typeText("培训\n")
        attachScreenshot(named: "24-us-shift-editor")
        app.buttons["保存班表"].tap()
        XCTAssertFalse(app.staticTexts["写班表"].waitForExistence(timeout: 1))
        attachScreenshot(named: "25-us-calendar-shift-saved")
    }

    func testCompanionHubShowsRemindersDrawersAndCapabilities() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-preview-us", "-ui-test-companion", "-app.skin", "day"]
        app.launch()

        let entry = app.buttons["us-companion-hub"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        XCTAssertTrue(app.descendants(matching: .any)["companion-hub"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["hub-reminders"].exists)
        XCTAssertTrue(app.buttons["hub-work-drawer"].exists)
        XCTAssertTrue(app.buttons["hub-personal-drawer"].exists)
        XCTAssertTrue(app.staticTexts["邮箱、笔友与群聊"].exists)
        XCTAssertTrue(app.staticTexts["照片与相册"].exists)
        attachScreenshot(named: "26-us-companion-hub")
    }

    private func waitForValue(_ value: String, on element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
