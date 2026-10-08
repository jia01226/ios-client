import XCTest

final class MoonlightInteractionTests: XCTestCase {
    func testFourTabsDiaryDateAndDrawerPrivacy() { Self.verify(in: self) }
    static func verify(in testCase: XCTestCase) {
        func capture(_ name: String) {
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; testCase.add(a)
        }
        testCase.continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-ui-test-moonlight", "-app.skin", "day"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-ke"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.descendants(matching: .any)["chat-line-switcher-test1"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["chat-line-switcher-light"].exists)
        capture("01-chat")
        app.buttons["tab-us"].tap()
        XCTAssertTrue(app.buttons["notes-add"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["anniversary-together"].exists)
        capture("02-us")
        // The airy anniversary/notes composition intentionally puts scheduling below the fold.
        let showMonth = app.buttons["us-show-month"]
        for _ in 0..<4 {
            if showMonth.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(showMonth.isHittable)
        showMonth.tap()
        XCTAssertTrue(app.buttons["period-start"].waitForExistence(timeout: 5))
        capture("03-month-calendar")
        app.buttons["tab-play"].tap()
        XCTAssertTrue(app.buttons["play-tarot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["play-duel"].exists)
        XCTAssertFalse(app.buttons["play-hut"].exists)
        capture("04-play")
        TarotInteractionChecks.verify(in: testCase, app: app)
        DuelInteractionChecks.verify(in: testCase, app: app)
        app.buttons["tab-drawer"].tap()
        XCTAssertTrue(app.buttons["diary-open-close"].waitForExistence(timeout: 8))
        capture("05-diary-cover")
        app.buttons["diary-rail--1"].tap()
        app.buttons["diary-open-close"].tap()
        XCTAssertTrue(app.staticTexts["diary-page-content"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["tab-drawer"].isHittable)
        let before = app.staticTexts["diary-page-date"].label
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.57))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.57))
        start.press(forDuration: 0.1, thenDragTo: end)
        let changed = NSPredicate(format: "label != %@", before)
        testCase.expectation(for: changed, evaluatedWith: app.staticTexts["diary-page-date"])
        testCase.waitForExpectations(timeout: 5)
        capture("06-diary-turned")
        app.buttons["diary-fullscreen-date-picker"].tap()
        XCTAssertTrue(app.buttons["diary-date-done"].waitForExistence(timeout: 5))
        capture("07-diary-date-picker")
        app.buttons["diary-date-done"].tap()
        app.buttons["diary-fullscreen-close"].tap()
        XCTAssertTrue(app.buttons["ke-drawer-tab"].waitForExistence(timeout: 6))
        app.buttons["ke-drawer-tab"].tap()
        KeepsakeInteractionChecks.verify(in: testCase, app: app, skin: "day")
        app.terminate()
        KeepsakeInteractionChecks.verifyNight(in: testCase)
    }
}
