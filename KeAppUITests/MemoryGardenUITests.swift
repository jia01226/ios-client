import XCTest

final class MemoryGardenUITests: XCTestCase {
    private func launch(_ extra: [String] = [], night: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-ui-test-memory", "-preview-memory",
                               "-us.home-reminders.enabled", "NO", "-app.skin", night ? "night" : "day"] + extra
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 2) {
            let deny = springboard.buttons["不允许"]
            if deny.exists { deny.tap() }
            else if springboard.buttons["Don't Allow"].exists { springboard.buttons["Don't Allow"].tap() }
        }
        XCTAssertTrue(app.buttons["tab-memory"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["memory-flower-list"].waitForExistence(timeout: 10))
        return app
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testFiveScenesLoveCorrectionAndRevive() {
        let app = launch()
        capture("89-01-moon")
        for (category, file) in [("关系", "water"), ("生活", "castle"), ("身体", "courtyard"), ("喜好", "glasshouse")] {
            app.buttons["memory-category-\(category)"].tap()
            capture("89-scene-\(file)")
        }
        app.buttons["memory-category-约定"].tap()
        app.buttons["memory-flower-list"].tap()
        let flower = app.buttons["memory-flower-fixture-0"]
        XCTAssertTrue(flower.waitForExistence(timeout: 4)); flower.tap()
        XCTAssertTrue(app.buttons["memory-love"].waitForExistence(timeout: 5))
        capture("89-02-flower-detail-undimmed")
        app.buttons["memory-love"].tap()
        XCTAssertTrue(app.buttons["这朵我很喜欢"].waitForExistence(timeout: 5))
        app.buttons["memory-correct"].tap()
        app.alerts.buttons["确认记错了"].tap()
        XCTAssertTrue(app.buttons["memory-withered"].waitForExistence(timeout: 5))
        app.buttons["memory-withered"].tap()
        let revive = app.buttons["memory-revive-fixture-0"]
        XCTAssertTrue(revive.waitForExistence(timeout: 5)); revive.tap()
        XCTAssertTrue(app.staticTexts["这里还没有枯掉的花。"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        app.buttons["memory-flower-list"].tap()
        XCTAssertTrue(app.buttons["memory-flower-fixture-0"].waitForExistence(timeout: 4))
    }
    func testQuotesPrivacySaveBookmarkNavigateAndConfirmDelete() {
        let app = launch()
        app.segmentedControls["memory-pages"].buttons["语录"].tap()
        XCTAssertTrue(app.buttons["quote-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["PRIVATE_QUOTE_HIDDEN"].exists)
        capture("89-03-quotes")
        app.buttons["tab-ke"].tap()
        let bubble = app.descendants(matching: .any)["message-bubble-ui-test-scroll-latest-0"].firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        bubble.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["message-action-quote"].waitForExistence(timeout: 5))
        app.buttons["message-action-quote"].tap()
        XCTAssertTrue(app.buttons["quote-save"].waitForExistence(timeout: 5))
        app.buttons["quote-save"].tap()
        XCTAssertTrue(app.images["message-bookmark-9101"].waitForExistence(timeout: 5))
        capture("89-04-bookmark")
        app.buttons["tab-memory"].tap()
        app.segmentedControls["memory-pages"].buttons["语录"].tap()
        let paper = app.buttons["quote-9101"]
        XCTAssertTrue(paper.waitForExistence(timeout: 5)); paper.tap()
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        app.buttons["tab-memory"].tap()
        app.segmentedControls["memory-pages"].buttons["语录"].tap()
        XCTAssertTrue(paper.waitForExistence(timeout: 5)); paper.swipeLeft()
        app.buttons["移出语录"].tap()
        XCTAssertTrue(app.alerts["从语录拿掉？"].waitForExistence(timeout: 3))
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(paper.exists)
        paper.swipeLeft()
        app.buttons["移出语录"].tap()
        app.alerts.buttons["拿掉"].tap()
        XCTAssertTrue(paper.waitForNonExistence(timeout: 5))
    }
    func testEmptyAndFailureAreDistinct() {
        var app = launch(["-ui-test-memory-empty"])
        XCTAssertTrue(app.staticTexts["柯还没开始种花，他每天会自己记下你们的事"].waitForExistence(timeout: 5))
        capture("89-05-empty")
        app.switches["memory-include-others"].coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["约定 · 93 条记忆"].waitForExistence(timeout: 5))
        capture("89-06-other-memories")
        app.terminate()
        app = launch(["-ui-test-memory-failure"])
        XCTAssertTrue(app.buttons["重试"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["柯还没开始种花，他每天会自己记下你们的事"].exists)
        capture("89-07-offline")
    }
    func testDense647NightPinchAndPan() {
        let app = launch(["-ui-test-memory-dense"], night: true)
        XCTAssertTrue(app.staticTexts["约定 · 647 条记忆"].waitForExistence(timeout: 8))
        capture("89-08-dense-night-clusters")
        let canvas = app.scrollViews["memory-garden-canvas"]
        XCTAssertTrue(canvas.exists)
        canvas.pinch(withScale: 2.5, velocity: 1)
        canvas.swipeUp()
        capture("89-09-dense-night-zoom")
        app.buttons["memory-flower-list"].tap()
        XCTAssertTrue(app.buttons["memory-flower-fixture-0"].waitForExistence(timeout: 5))
    }

    func testLargeTextKeepsGardenControlsAvailable() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["memory-flower-list"].isHittable)
        app.buttons["memory-flower-list"].tap()
        XCTAssertTrue(app.buttons["memory-flower-fixture-0"].waitForExistence(timeout: 5))
        capture("89-10-large-text-list")
    }

    func testStickyAckRestoreAcrossUsAndDrawer() {
        let app = launch(["-ui-test-moonlight"])
        app.buttons["tab-us"].tap()
        let ack = app.buttons["note-ack-fixture-ke"]
        XCTAssertTrue(ack.waitForExistence(timeout: 6))
        if !ack.isHittable { app.swipeUp() }
        ack.tap()
        XCTAssertTrue(ack.waitForNonExistence(timeout: 5))
        app.buttons["notes-open-archive"].tap()
        let restore = app.buttons["note-restore-fixture-ke"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        capture("89-11-sticky-server-acked")
        restore.tap()
        XCTAssertTrue(restore.waitForNonExistence(timeout: 5))
        app.buttons["notes-list-close"].tap()
        XCTAssertTrue(ack.waitForExistence(timeout: 5))
    }
}
