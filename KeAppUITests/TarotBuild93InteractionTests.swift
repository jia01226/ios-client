import XCTest

enum TarotBuild93InteractionTests {
    static func verify(in test: XCTestCase) {
        test.continueAfterFailure = false
        for spread in ["one", "three", "celtic"] {
            run(spread, in: test)
        }
    }

    private static func capture(_ name: String, in test: XCTestCase) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; test.add(attachment)
    }

    private static func reach(_ element: XCUIElement, app: XCUIApplication, up: Bool = true) {
        for _ in 0..<5 {
            if element.isHittable { return }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }

    private static func run(_ spread: String, in test: XCTestCase) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-ui-test-tarot-handoff", "-app.skin", spread == "one" ? "night" : "day"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-play"].waitForExistence(timeout: 10))
        app.buttons["tab-play"].tap(); app.buttons["play-tarot"].tap()
        let spreadButton = app.buttons["tarot-spread-\(spread)"]
        XCTAssertTrue(spreadButton.waitForExistence(timeout: 5))
        if spread == "celtic" {
            // A user can switch from an already shuffled default three-card spread to ten.
            let initialDraw = app.buttons["tarot-draw"]
            reach(initialDraw, app: app); initialDraw.tap(); sleep(3)
            reach(spreadButton, app: app, up: false)
            XCTAssertTrue(spreadButton.isEnabled)
        }
        spreadButton.tap()
        let field = app.descendants(matching: .any).matching(identifier: "tarot-question").firstMatch
        XCTAssertTrue(field.isEnabled); field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let question = "Build93 \(spread) question"
        field.typeText(question)
        XCTAssertTrue((field.value as? String ?? "").contains(question))
        capture("tarot93-\(spread)-question-keyboard", in: test)
        app.buttons["tarot-question-done"].tap()
        let draw = app.buttons["tarot-draw"]
        reach(draw, app: app); draw.tap(); sleep(3)

        // Editing a question after shuffle must not disable it or discard the locked deck.
        reach(field, app: app, up: false)
        XCTAssertTrue(field.isEnabled); field.tap(); field.typeText(" updated")
        app.buttons["tarot-question-done"].tap()
        let fan = app.descendants(matching: .any)["tarot-fan"]
        // Move the entire semicircle into view, not just its topmost hittable point.
        for _ in 0..<5 {
            if fan.frame.maxY < app.frame.maxY - 80 { break }
            app.swipeUp()
        }
        XCTAssertTrue(fan.isHittable)
        XCTAssertGreaterThan(fan.frame.minY, app.frame.minY)
        capture("tarot93-\(spread)-full-fan", in: test)
        let count = spread == "one" ? 1 : spread == "three" ? 3 : 10
        for index in 0..<count {
            let angle = Double.pi + Double(index + 1) / Double(count + 1) * Double.pi
            let point = fan.coordinate(withNormalizedOffset: CGVector(
                dx: 0.5 + cos(angle) * 0.32,
                dy: (0.60 - 0.105 + sin(angle) * 0.32) / 0.60))
            point.tap(); sleep(1)
            XCTAssertEqual(app.staticTexts["tarot-selection-count"].label, "已选 \(index) / \(count)")
            XCTAssertTrue(app.buttons["tarot-confirm-preview"].exists)
            point.tap(); sleep(1)
            XCTAssertEqual(app.staticTexts["tarot-selection-count"].label, "已选 \(index + 1) / \(count)")
            if spread == "three", index == 0 {
                let selected = app.buttons["tarot-card-0"]
                XCTAssertTrue(selected.isHittable)
                selected.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .press(forDuration: 0.15, thenDragTo: point)
                sleep(1)
                XCTAssertEqual(app.staticTexts["tarot-selection-count"].label, "已选 0 / 3")
                point.tap(); sleep(1); point.tap(); sleep(1)
                XCTAssertEqual(app.staticTexts["tarot-selection-count"].label, "已选 1 / 3")
            }
        }
        capture("tarot93-\(spread)-selected", in: test)
        let flip = app.buttons["tarot-flip"]
        reach(flip, app: app); XCTAssertTrue(flip.isEnabled); flip.tap()
        let handoff = app.buttons["tarot-ask-ke"]
        XCTAssertTrue(handoff.waitForExistence(timeout: 15))
        capture("tarot93-\(spread)-revealed", in: test)
        if spread == "three" {
            let selected = app.buttons["tarot-card-0"]
            reach(selected, app: app, up: false); selected.tap()
            XCTAssertTrue(app.buttons["tarot-inspector-close"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["tarot-inspector-title"].label, "月亮 · 逆位")
            app.buttons["tarot-inspector-close"].tap()
        }
        reach(handoff, app: app); handoff.tap()
        XCTAssertTrue(app.descendants(matching: .any)["chat-composer"].waitForExistence(timeout: 10))
        let sent = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "[塔罗#7]", question + " updated")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 8))
        // This response can only appear after the view model actually sends and receives a receipt.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "牌面核对：月亮")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["发送失败"].exists)
        XCTAssertFalse(app.buttons["tarot-close"].exists)
        capture("tarot93-\(spread)-auto-sent", in: test)
        app.terminate()
    }
}
