import XCTest

final class MemoryReviewInteractionTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func openDeck(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-memory-review", "-app.skin", "day"] + extra
        app.launch()
        app.buttons["回忆"].tap()
        let entry = app.buttons["memory-review-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.staticTexts["review-fact"].waitForExistence(timeout: 5))
        return app
    }
    func testSourceNoteSwipeAndUndo() {
        let app = openDeck()
        let fact = app.staticTexts["review-fact"]
        XCTAssertEqual(fact.label, "喜欢有酸味的蓝莓果酱")
        let original = app.buttons["review-original"]
        original.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "完整原文到这里结束")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
        app.buttons["review-note"].tap()
        let editor = app.textViews["review-note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap(); editor.typeText("Only on weekends")
        app.buttons["review-save-note"].tap()
        XCTAssertTrue(app.buttons["review-note"].waitForExistence(timeout: 3))
        XCTAssertEqual(fact.label, "喜欢有酸味的蓝莓果酱")
        app.otherElements["review-card"].swipeRight()
        let second = NSPredicate(format: "label == %@", "周末想试试陶艺")
        expectation(for: second, evaluatedWith: fact)
        waitForExpectations(timeout: 5)
        app.buttons["review-undo"].tap()
        XCTAssertTrue(app.staticTexts["喜欢有酸味的蓝莓果酱"].waitForExistence(timeout: 3))
        app.otherElements["review-card"].swipeLeft()
        expectation(for: second, evaluatedWith: fact)
        waitForExpectations(timeout: 5)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "memory-review-deck"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testUpSwipeRequestsNoteThenDefers() {
        let app = openDeck()
        app.otherElements["review-card"].swipeUp()
        let editor = app.textViews["review-note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap(); editor.typeText("Need context")
        app.buttons["完成"].tap()
        app.otherElements["review-card"].swipeUp()
        XCTAssertTrue(app.staticTexts["周末想试试陶艺"].waitForExistence(timeout: 5))
        app.buttons["暂缓 1"].tap()
        XCTAssertTrue(app.staticTexts["喜欢有酸味的蓝莓果酱"].waitForExistence(timeout: 3))
    }
    func testReviewScreenshotsLightDarkAndLargeType() {
        for (name, arguments) in [("phone-light", [String]()), ("phone-dark", ["-app.skin", "night"]),
                                  ("phone-large", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"])] {
            let app = openDeck(extra: arguments)
            XCTAssertTrue(app.buttons["review-original"].isHittable)
            XCTAssertTrue(app.buttons["review-accept"].isHittable)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = name; shot.lifetime = .keepAlways; add(shot)
            if name == "phone-light" || name == "phone-large" {
                app.buttons["review-original"].tap()
                let original = XCTAttachment(screenshot: app.screenshot())
                original.name = name == "phone-light" ? "phone-original" : "phone-original-large"
                original.lifetime = .keepAlways; add(original)
                app.buttons["完成"].tap()
            }
            if name == "phone-light" {
                app.buttons["review-note"].tap()
                app.textViews["review-note-editor"].tap()
                let note = XCTAttachment(screenshot: app.screenshot())
                note.name = "phone-note"; note.lifetime = .keepAlways; add(note)
            }
            app.terminate()
        }
    }

}
