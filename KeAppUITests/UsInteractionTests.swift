import XCTest

final class UsInteractionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMoonOrbitSelectionRotationAndTabRoundTrip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control"]
        app.launch()

        let usTab = app.buttons["我们"]
        XCTAssertTrue(usTab.waitForExistence(timeout: 5))
        usTab.tap()

        let moon = app.descendants(matching: .any)["us-moon-orbit-selector"]
        XCTAssertTrue(moon.waitForExistence(timeout: 3))
        XCTAssertTrue((moon.value as? String)?.hasPrefix("表白的日子，320天") == true)
        attachScreenshot(named: "20-us-default-anniversary")

        app.buttons["柯"].tap()
        XCTAssertTrue(app.buttons["我们"].waitForExistence(timeout: 2))
        app.buttons["我们"].tap()

        XCTAssertTrue(moon.waitForExistence(timeout: 2))
        XCTAssertTrue((moon.value as? String)?.hasPrefix("表白的日子，320天") == true)
        attachScreenshot(named: "23-us-tab-round-trip")
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
