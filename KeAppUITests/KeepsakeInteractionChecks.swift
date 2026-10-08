import XCTest

enum KeepsakeInteractionChecks {
    static func verify(in testCase: XCTestCase, app: XCUIApplication, skin: String) {
        func capture(_ suffix: String) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "keepsake-\(skin)-\(suffix)"
            shot.lifetime = .keepAlways
            testCase.add(shot)
        }
        func waitValue(_ element: XCUIElement, _ value: String) {
            let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 6), .completed)
        }
        func scrollTo(_ element: XCUIElement) {
            for _ in 0..<4 {
                if element.isHittable { break }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.80))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.40)))
            }
            XCTAssertTrue(element.isHittable)
        }

        XCTAssertTrue(app.buttons["drawer-pull"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["drawer-private-locked"].exists)
        capture("01-closed")
        // Exercise the actual illustration drag, not only the fallback button.
        let art = app.descendants(matching: .any).matching(identifier: "drawer-artwork").firstMatch
        art.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.47))
            .press(forDuration: 0.15, thenDragTo: art.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)))
        waitValue(app.buttons["drawer-pull"], "已拉开")
        XCTAssertTrue(app.buttons["drawer-letter-501"].waitForExistence(timeout: 8))
        capture("02-open")
        let teaser = app.descendants(matching: .any).matching(identifier: "drawer-teaser-503").firstMatch
        scrollTo(teaser)
        capture("03-scroll-list")
        teaser.tap()
        XCTAssertFalse(app.buttons["drawer-reader-close"].exists)
        XCTAssertFalse(app.staticTexts["PRIVATE_PAYLOAD_MUST_NOT_RENDER"].exists)
        XCTAssertFalse(app.staticTexts["不应显示的私密标题"].exists)
        XCTAssertFalse(app.staticTexts["不应显示的私密提示"].exists)
        XCTAssertFalse(app.staticTexts["TEASER_CONTENT_MUST_NOT_RENDER"].exists)
        XCTAssertFalse(app.staticTexts["TEASER_TITLE_MUST_NOT_RENDER"].exists)

        let letter = app.buttons["drawer-letter-501"]
        // Released letter is directly above the teaser, so a small downward scroll brings it back.
        if !letter.isHittable { app.swipeDown() }
        XCTAssertTrue(letter.isHittable)
        letter.tap()
        let body = app.staticTexts["drawer-reader-content"]
        XCTAssertTrue(body.waitForExistence(timeout: 6))
        XCTAssertEqual(body.label, "慢慢来，我会陪着你。")
        capture("04-letter-unrolled")
        app.buttons["drawer-reader-close"].tap()
        XCTAssertTrue(app.buttons["drawer-letter-501"].waitForExistence(timeout: 6))
        let pull = app.buttons["drawer-pull"]
        for _ in 0..<4 {
            if pull.isHittable { break }
            app.swipeDown()
        }
        pull.tap()
        waitValue(pull, "已合上")
        XCTAssertFalse(app.buttons["drawer-letter-501"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["drawer-private-locked"].exists)
    }

    static func verifyNight(in testCase: XCTestCase) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-ui-test-moonlight", "-app.skin", "night"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-ke"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.descendants(matching: .any)["chat-line-switcher-test1"].exists)
        app.buttons["tab-drawer"].tap()
        app.buttons["ke-drawer-tab"].tap()
        verify(in: testCase, app: app, skin: "night")
        app.terminate()
    }
}
