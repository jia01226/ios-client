import XCTest

final class MemoryExpeditionUITests: XCTestCase {
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func launch(_ extras: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-ui-test-memory", "-preview-memory",
                               "-preview-expedition", "-us.home-reminders.enabled", "NO", "-app.skin", "night"] + extras
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 2) {
            if springboard.buttons["不允许"].exists { springboard.buttons["不允许"].tap() }
            else if springboard.buttons["Don't Allow"].exists { springboard.buttons["Don't Allow"].tap() }
        }
        if extras.contains("-preview-flower-study") {
            XCTAssertTrue(app.staticTexts["expedition-material-study"].waitForExistence(timeout: 12))
        } else { XCTAssertTrue(app.buttons["expedition-deeper"].waitForExistence(timeout: 12)) }
        return app
    }
    func testExploreFlowerMemoryAndReturn() {
        let app = launch()
        capture("90-01-moon-entrance")
        let flower = app.buttons["expedition-flower-expedition-0"]
        XCTAssertTrue(flower.isHittable)
        flower.tap()
        XCTAssertTrue(app.buttons["expedition-close"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["示例内容，不写入真实记忆"].exists)
        capture("90-02-memory-emerges")
        app.buttons["expedition-close"].tap()
        XCTAssertTrue(flower.waitForExistence(timeout: 3))
        app.buttons["expedition-deeper"].tap()
        XCTAssertTrue(app.staticTexts["月下山茶 · 深处"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["expedition-flower-expedition-0"].exists)
        capture("90-03-deeper-garden")
        app.buttons["expedition-back"].tap()
        XCTAssertTrue(flower.waitForExistence(timeout: 3))
        app.buttons["expedition-light"].tap()
        for (category, name) in [("关系", "water"), ("生活", "castle"), ("身体", "courtyard"), ("喜好", "glasshouse")] {
            app.buttons["expedition-category-\(category)"].tap()
            capture("90-day-\(name)")
        }
    }
    func testPanAndAccessibleList() {
        let app = launch()
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.49))
        from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.52)))
        app.buttons["expedition-list"].tap()
        XCTAssertTrue(app.buttons["expedition-list-expedition-0"].waitForExistence(timeout: 4))
        app.buttons["expedition-list-expedition-0"].tap()
        XCTAssertTrue(app.buttons["expedition-close"].waitForExistence(timeout: 4))
        app.buttons["expedition-close"].tap()
        XCTAssertTrue(app.buttons["expedition-deeper"].isHittable)
    }
    func testSpiritFrameAndCategoryCancellation() {
        let app = launch(["-preview-spirit-frame"])
        app.buttons["expedition-flower-expedition-0"].tap()
        capture("90-spirit-flight-frame")
        XCTAssertFalse(app.buttons["expedition-close"].exists)
        app.buttons["expedition-category-关系"].tap()
        XCTAssertTrue(app.staticTexts["水边山茶"].exists)
        XCTAssertFalse(app.buttons["expedition-close"].exists)
    }
    func testNineFlowerMaterialStudy() {
        let app = launch(["-preview-flower-study"])
        XCTAssertTrue(app.staticTexts["紧苞"].exists)
        XCTAssertTrue(app.staticTexts["背面"].exists)
        capture("90-nine-flower-study")
    }
}
