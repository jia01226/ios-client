import XCTest

/// 126：「柯的」顶上不再有配色小菜单（设计稿只留右上月牙）。纸色在设置抽屉「素笺」页里选：
/// 点月牙 → 素笺 → 五款纸色。这里照旧验五款都能选、重开 App 还记得、六个入口照旧能开能关。
final class CamelliaPaletteUITests: XCTestCase {
    private let palettes = [("blush", "粉白"), ("mist", "浅雾蓝"), ("white", "冷白"), ("ivory", "暖白"), ("cream", "浅米色")]
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(skin: String = "day", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-ui-test-moonlight", "-ui-test-memory", "-ui-test-reduce-motion", "-app.skin", skin] + extra
        app.launch()
        XCTAssertTrue(app.buttons["tab-drawer"].waitForExistence(timeout: 15))
        app.buttons["tab-drawer"].tap()
        XCTAssertTrue(app.buttons["home-settings-moon"].waitForExistence(timeout: 10))
        return app
    }

    /// 月牙 → 设置抽屉 → 素笺
    private func openPaperPage(_ app: XCUIApplication) {
        app.buttons["home-settings-moon"].tap()
        let paper = app.buttons["素笺"].firstMatch
        XCTAssertTrue(paper.waitForExistence(timeout: 6))
        paper.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testFiveColorsAndPersistenceAfterRelaunch() {
        let app = launch()
        openPaperPage(app)
        for (key, label) in palettes {
            let choice = app.buttons[label].firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 4), key)
            XCTAssertFalse(app.buttons["原蓝"].exists)
            choice.tap()
            XCTAssertTrue(choice.isSelected, key)
            capture("camellia-126-\(key)")
        }
        app.terminate()
        app.launch()
        app.buttons["tab-drawer"].tap()
        XCTAssertTrue(app.buttons["home-settings-moon"].waitForExistence(timeout: 10))
        openPaperPage(app)
        XCTAssertTrue(app.buttons["浅米色"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["浅米色"].firstMatch.isSelected)
        capture("camellia-126-persisted")
    }

    func testSixEntrancesStillOpenAndClose() {
        let app = launch()
        for (entry, close) in [("diary", "ke-space-close"), ("dream", "dream-close"), ("drawer", "ke-space-close"), ("tarot", "tarot-close"), ("moments", "moments-close"), ("memory", "memory-close")] {
            let flower = app.buttons.matching(identifier: "camellia-\(entry)").firstMatch
            XCTAssertTrue(flower.waitForExistence(timeout: 6))
            flower.tap()
            XCTAssertTrue(app.buttons[close].waitForExistence(timeout: 10), "Entry: \(entry)")
            capture("camellia-126-entry-\(entry)")
            app.buttons[close].tap()
            XCTAssertTrue(app.buttons["home-settings-moon"].waitForExistence(timeout: 6))
        }
    }

    func testMoonUnderNightSkinAndLargeText() {
        let app = launch(skin: "night", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"])
        let moon = app.buttons["home-settings-moon"]
        XCTAssertTrue(moon.isHittable)
        openPaperPage(app)
        XCTAssertTrue(app.buttons["暖白"].firstMatch.waitForExistence(timeout: 4))
        app.buttons["暖白"].firstMatch.tap()
        capture("camellia-126-night-large-text")
    }
}
