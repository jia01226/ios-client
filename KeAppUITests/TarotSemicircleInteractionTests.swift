import XCTest

enum TarotSemicircleInteractionTests {
    static func capture(_ name: String, in test: XCTestCase) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; test.add(attachment)
    }
    static func chooseThree(in test: XCTestCase, app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tarot-draw"].waitForExistence(timeout: 8))
        app.buttons["tarot-draw"].tap()
        let fan = app.otherElements["tarot-fan"]
        XCTAssertTrue(fan.waitForExistence(timeout: 8))
        // The server fixture returns immediately; let the shuffle/unfold finish.
        sleep(3)
        capture("tarot91-01-full-fan", in: test)
        let center = fan.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        center.tap()
        XCTAssertTrue(app.buttons["tarot-confirm-preview"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["tarot-selection-count"].label, "已选 0 / 3")
        capture("tarot91-02-first-tap-lift", in: test)
        center.tap()
        sleep(1)
        XCTAssertEqual(app.staticTexts["tarot-selection-count"].label, "已选 1 / 3")
        // Drag the first selected card back to the fan, preserving the remaining deck.
        let selected = app.buttons["tarot-card-0"]
        XCTAssertTrue(selected.exists)
        selected.press(forDuration: 0.15, thenDragTo: center)
        sleep(1)
        XCTAssertEqual(app.staticTexts["tarot-selection-count"].label, "已选 0 / 3")
        for point in [CGVector(dx: 0.25, dy: 0.38), CGVector(dx: 0.5, dy: 0.15), CGVector(dx: 0.75, dy: 0.38)] {
            let target = fan.coordinate(withNormalizedOffset: point)
            target.tap(); sleep(1); target.tap(); sleep(1)
        }
        XCTAssertEqual(app.staticTexts["tarot-selection-count"].label, "已选 3 / 3")
        capture("tarot91-03-three-face-down", in: test)
        let flip = app.buttons["tarot-flip"]
        if !flip.isHittable { app.swipeUp() }
        XCTAssertTrue(flip.isEnabled); flip.tap()
        XCTAssertTrue(app.buttons["tarot-ask-ke"].waitForExistence(timeout: 15))
        capture("tarot91-04-revealed", in: test)
    }
    static func verify(in test: XCTestCase) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-app.skin", "day"]
        app.launch()
        XCTAssertTrue(app.buttons["玩"].waitForExistence(timeout: 10))
        app.buttons["玩"].tap()
        app.buttons["play-tarot"].tap()
        chooseThree(in: test, app: app)
        let card = app.buttons["tarot-card-0"]
        if !card.isHittable { app.swipeDown() }
        card.tap()
        XCTAssertTrue(app.buttons["tarot-inspector-close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["tarot-inspector-title"].label, "月亮 · 逆位")
        capture("tarot91-05-reversed-inspector", in: test)
        app.buttons["tarot-inspector-close"].tap()
        let handoff = app.buttons["tarot-ask-ke"]
        if !handoff.isHittable { app.swipeUp() }
        handoff.tap()
        XCTAssertFalse(app.buttons["tarot-close"].waitForExistence(timeout: 2))
        capture("tarot91-06-handoff", in: test)
        app.terminate()
    }
}
