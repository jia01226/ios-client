import XCTest

final class UsInteractionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMoonOrbitSelectionRotationAndTabRoundTrip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-us-cosmos-preview"]
        app.launch()

        let usTab = app.buttons["我们"]
        XCTAssertTrue(usTab.waitForExistence(timeout: 5))
        usTab.tap()

        let moon = app.descendants(matching: .any)["us-moon-orbit-selector"]
        XCTAssertTrue(moon.waitForExistence(timeout: 3))
        XCTAssertEqual(moon.value as? String, "我们的纪念日")
        attachScreenshot(named: "20-us-default-anniversary")

        let remembers = app.descendants(matching: .any)["us-ke-remembers"]
        XCTAssertTrue(remembers.waitForExistence(timeout: 3))
        let scrollStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.70))
        let scrollEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.30))
        scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd)
        attachScreenshot(named: "20b-us-ke-remembers")

        scrollEnd.press(forDuration: 0.05, thenDragTo: scrollStart)

        let myBirthday = app.descendants(matching: .any)["us-orbit-event-0"]
        XCTAssertTrue(myBirthday.waitForExistence(timeout: 2))
        myBirthday.tap()
        waitForValue("我的生日", on: moon)
        attachScreenshot(named: "21-us-my-birthday-selected")

        moon.swipeLeft(velocity: .slow)
        Thread.sleep(forTimeInterval: 0.7)
        XCTAssertEqual(moon.value as? String, "我的生日")
        attachScreenshot(named: "22-us-moon-rotated")

        app.buttons["柯"].tap()
        XCTAssertTrue(app.buttons["我们"].waitForExistence(timeout: 2))
        app.buttons["我们"].tap()

        XCTAssertTrue(moon.waitForExistence(timeout: 2))
        XCTAssertEqual(moon.value as? String, "我的生日")
        attachScreenshot(named: "23-us-tab-round-trip")
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
