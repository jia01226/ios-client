import XCTest

final class CamelliaPaletteUITests: XCTestCase {
    private let palettes = [("mist", "浅雾蓝"), ("white", "冷白"), ("ivory", "暖白"), ("cream", "浅米色")]
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(skin: String = "day") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-ui-test-moonlight", "-ui-test-memory", "-ui-test-reduce-motion", "-app.skin", skin]
        app.launch()
        XCTAssertTrue(app.buttons["tab-drawer"].waitForExistence(timeout: 15))
        app.buttons["tab-drawer"].tap()
        XCTAssertTrue(app.buttons["camellia-palette-picker"].waitForExistence(timeout: 10))
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testFourColorsAndPersistenceAfterRelaunch() {
        let app = launch()
        for (key, label) in palettes {
            let picker = app.buttons["camellia-palette-picker"]
            XCTAssertTrue(picker.isHittable)
            picker.tap()
            let choice = app.buttons["camellia-palette-\(key)"]
            XCTAssertTrue(choice.waitForExistence(timeout: 4))
            XCTAssertFalse(app.buttons["原蓝"].exists)
            choice.tap()
            XCTAssertEqual(picker.value as? String, label)
            capture("camellia-99-\(key)")
        }
        app.terminate()
        app.launch()
        app.buttons["tab-drawer"].tap()
        XCTAssertTrue(app.buttons["camellia-palette-picker"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["camellia-palette-picker"].value as? String, "浅米色")
        capture("camellia-99-persisted")
    }

    func testSixEntrancesStillOpenAndClose() {
        let app = launch()
        for (entry, close) in [("diary", "ke-space-close"), ("dream", "dream-close"), ("drawer", "ke-space-close"), ("tarot", "tarot-close"), ("moments", "moments-close"), ("memory", "memory-close")] {
            let flower = app.buttons.matching(identifier: "camellia-\(entry)").firstMatch
            XCTAssertTrue(flower.waitForExistence(timeout: 6))
            flower.tap()
            XCTAssertTrue(app.buttons[close].waitForExistence(timeout: 10), "Entry: \(entry)")
            capture("camellia-99-entry-\(entry)")
            app.buttons[close].tap()
            XCTAssertTrue(app.buttons["camellia-palette-picker"].waitForExistence(timeout: 6))
        }
    }

    func testPaletteControlUnderNightSkinAndLargeText() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-ui-test-moonlight", "-ui-test-memory", "-ui-test-reduce-motion", "-app.skin", "night", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-drawer"].waitForExistence(timeout: 15))
        app.buttons["tab-drawer"].tap()
        let picker = app.buttons["camellia-palette-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertTrue(picker.isHittable)
        picker.tap()
        XCTAssertTrue(app.buttons["camellia-palette-ivory"].waitForExistence(timeout: 4))
        app.buttons["camellia-palette-ivory"].tap()
        capture("camellia-99-night-large-text")
    }
}
