import XCTest

enum TarotInteractionChecks {
    static func verify(in testCase: XCTestCase, app: XCUIApplication) {
        func capture(_ name: String) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = name; shot.lifetime = .keepAlways; testCase.add(shot)
        }
        app.buttons["play-tarot"].tap()
        TarotSemicircleInteractionTests.chooseThree(in: testCase, app: app)
        let card = app.buttons["tarot-card-0"]
        if !card.isHittable { app.swipeDown() }
        let before = card.label
        card.tap()
        XCTAssertTrue(app.buttons["tarot-inspector-close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["tarot-inspector-title"].label, "月亮 · 逆位")
        let zoom = app.scrollViews["tarot-card-zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 20))
        capture("tarot-03-fullscreen-reversed")
        zoom.pinch(withScale: 2, velocity: 1)
        let enlarged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "1.0"), object: zoom)
        XCTAssertEqual(XCTWaiter.wait(for: [enlarged], timeout: 5), .completed)
        capture("tarot-04-zoom-detail")
        zoom.doubleTap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1.0"), object: zoom)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        app.buttons["tarot-next"].tap()
        XCTAssertEqual(app.staticTexts["tarot-inspector-title"].label, "圣杯二 · 正位")
        app.buttons["tarot-previous"].tap()
        XCTAssertEqual(app.staticTexts["tarot-inspector-title"].label, "月亮 · 逆位")
        app.buttons["tarot-inspector-close"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, before, "Inspecting a card must preserve the drawn result")
        for _ in 0..<4 {
            if app.buttons["tarot-close"].isHittable { break }
            app.swipeDown()
        }
        app.buttons["tarot-close"].tap()
        XCTAssertTrue(app.buttons["tab-drawer"].waitForExistence(timeout: 5))
    }
}
