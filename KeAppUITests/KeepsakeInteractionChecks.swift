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
        let handle = app.descendants(matching: .any).matching(identifier: "drawer-letter-handle").firstMatch
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.15, thenDragTo: handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 2.0)))
        waitValue(app.buttons["drawer-pull"], "已拉开")
        XCTAssertTrue(app.buttons["drawer-letter-501"].waitForExistence(timeout: 8))
        capture("02-open")
        let teaser = app.descendants(matching: .any).matching(identifier: "drawer-teaser-503").firstMatch
        let letterInterior = app.scrollViews["drawer-letter-interior"]
        for _ in 0..<3 {
            if teaser.isHittable { break }
            letterInterior.swipeUp()
        }
        XCTAssertTrue(teaser.isHittable)
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
        if !letter.isHittable { letterInterior.swipeDown() }
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

        let notesPull = app.buttons["drawer-notes-pull"]
        notesPull.tap()
        XCTAssertTrue(app.buttons["drawer-notes-close"].waitForExistence(timeout: 6))
        capture("05-notes-drawer")
        let keNote = app.buttons["note-open-fixture-ke"]
        scrollTo(keNote)
        XCTAssertFalse(app.buttons["notes-add"].exists)
        XCTAssertFalse(app.buttons["note-open-fixture-jia"].exists, "Old user notes must not appear among Ke's reminders")
        let interior = app.descendants(matching: .any).matching(identifier: "drawer-notes-interior").firstMatch
        XCTAssertTrue(interior.frame.contains(keNote.frame), "Paper must be inside the actual drawer, not in a list below it")
        keNote.tap()
        XCTAssertTrue(app.buttons["drawer-note-put-back"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["drawer-note-content"].label, "慢慢来，我陪着你。")
        XCTAssertFalse(app.textViews["note-editor"].exists, "Ke's note is read-only")
        XCTAssertFalse(app.buttons["note-save"].exists)
        capture("06-note-lifted")
        app.buttons["drawer-note-put-back"].tap()
        XCTAssertTrue(keNote.waitForExistence(timeout: 5))
        if skin == "day" {
            app.buttons["note-ack-fixture-ke"].tap()
            let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: keNote)
            XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 6), .completed)
            capture("06b-note-acknowledged")
            app.buttons["tab-us"].tap()
            XCTAssertTrue(app.buttons["notes-all"].waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["note-open-fixture-ke"].exists, "Acknowledgement must update the other notes view")
            let archive = app.buttons["notes-open-archive"]
            scrollTo(archive)
            archive.tap()
            let restore = app.buttons["note-restore-fixture-ke"]
            XCTAssertTrue(restore.waitForExistence(timeout: 5))
            capture("07-acknowledged-note-in-us")
            restore.tap()
            let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: restore)
            XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 6), .completed)
            XCTAssertFalse(app.textViews["note-editor"].exists)
            app.buttons["notes-list-close"].tap()
            XCTAssertTrue(app.buttons["note-open-fixture-ke"].waitForExistence(timeout: 6))
            capture("08-note-restored")
        } else {
            let close = app.buttons["drawer-notes-close"]
            for _ in 0..<4 {
                if close.isHittable { break }
                app.swipeDown()
            }
            close.tap()
            XCTAssertTrue(notesPull.waitForExistence(timeout: 6))
            waitValue(notesPull, "已合上")
            XCTAssertTrue(app.descendants(matching: .any)["drawer-private-locked"].exists)
        }
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
