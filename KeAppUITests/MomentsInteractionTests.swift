import XCTest

struct MomentsInteractionChecks {
    private let testCase: XCTestCase

    static func verify(in testCase: XCTestCase) {
        testCase.continueAfterFailure = false
        let checks = Self(testCase: testCase)
        checks.verifyTimelinePublishingReactionsAndOwnContentPermissions()
        checks.verifyFailedPublishRetainsDraftAndCanRetryAtNight()
    }

    private func verifyTimelinePublishingReactionsAndOwnContentPermissions() {
        let app = launch(skin: "day")
        openMoments(app)
        XCTAssertTrue(app.descendants(matching: .any)["moments-cover"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["moment-content-702"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["moment-content-702"].label, "给今天留一张照片。")
        capture("moments-day-cover-and-feed")

        let photo = app.buttons["moment-image-702"]
        reveal(photo, in: app)
        photo.tap()
        XCTAssertTrue(app.buttons["moment-image-close"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.descendants(matching: .any)["moment-image-preview"].exists)
        capture("moments-day-photo")
        app.buttons["moment-image-close"].tap()

        let like = app.buttons["moment-like-702"]
        reveal(like, in: app)
        XCTAssertEqual(like.value as? String, "未赞")
        like.tap()
        waitValue(like, equals: "已赞")
        like.tap()
        waitValue(like, equals: "未赞")

        let ownMenu = app.buttons["moment-menu-702"]
        reveal(ownMenu, in: app, direction: .down)
        ownMenu.tap()
        app.buttons["编辑动态"].tap()
        let edit = app.textViews["moment-editor-text"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap(); edit.typeText("补上一句。"); app.buttons["moment-editor-save"].tap()
        waitLabel(app.staticTexts["moment-content-702"], contains: "补上一句。")

        let keComment = app.descendants(matching: .any)["moment-reply-801"]
        reveal(keComment, in: app)
        XCTAssertFalse(app.buttons["moment-menu-701"].exists, "Ke's post must not offer edit or delete")
        XCTAssertFalse(app.buttons["moment-comment-menu-801"].exists, "Ke's comment must not offer edit or delete")
        let ownCommentMenu = app.buttons["moment-comment-menu-802"]
        reveal(ownCommentMenu, in: app)
        ownCommentMenu.tap()
        app.buttons["编辑评论"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap(); edit.typeText("花开得真好。"); app.buttons["moment-editor-save"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "花开得真好。")).firstMatch.waitForExistence(timeout: 6))

        let comment = app.buttons["moment-comment-701"]
        reveal(comment, in: app, direction: .down)
        comment.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap(); edit.typeText("这句评论会留下。"); app.buttons["moment-editor-save"].tap()
        let newComment = app.buttons["moment-comment-menu-803"]
        reveal(newComment, in: app)
        XCTAssertTrue(app.staticTexts["佳佳：这句评论会留下。"].exists)
        capture("moments-day-reactions-and-permissions")
        newComment.tap()
        app.buttons["删除评论"].tap()
        confirmDeletion(in: app)
        waitGone(newComment)
        XCTAssertTrue(app.descendants(matching: .any)["moment-reply-801"].exists)

        app.buttons["moments-compose"].tap()
        let draft = app.textViews["moment-draft-text"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap(); draft.typeText("把这个下午留在朋友圈。"); app.buttons["moment-publish"].tap()
        waitGone(draft)
        let published = app.staticTexts["moment-content-703"]
        reveal(published, in: app, direction: .down)
        XCTAssertEqual(published.label, "把这个下午留在朋友圈。")
        capture("moments-day-published")
        let publishedMenu = app.buttons["moment-menu-703"]
        reveal(publishedMenu, in: app, direction: .down)
        publishedMenu.tap()
        app.buttons["删除动态"].tap()
        confirmDeletion(in: app)
        waitGone(published)
        XCTAssertTrue(app.buttons["moment-menu-702"].exists)
        app.buttons["moments-close"].tap()
        XCTAssertTrue(app.buttons["play-moments"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["moments-unread"].exists, "Opening the loaded feed marks its sampled activity as read")
        app.terminate()
    }

    private func verifyFailedPublishRetainsDraftAndCanRetryAtNight() {
        let app = launch(skin: "night", extra: ["-ui-test-moments-publish-failure"])
        openMoments(app)
        app.buttons["moments-compose"].tap()
        let draft = app.textViews["moment-draft-text"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        let text = "网络没接上时，这句话也要留着。"
        draft.tap(); draft.typeText(text)
        app.buttons["moment-publish"].tap()
        XCTAssertTrue(app.staticTexts["moment-editor-error"].waitForExistence(timeout: 8))
        XCTAssertEqual(draft.value as? String, text)
        XCTAssertTrue(app.buttons["moment-publish"].isEnabled)
        capture("moments-night-failure-keeps-draft")
        app.buttons["moment-draft-close"].tap()
        XCTAssertTrue(app.buttons["moments-compose"].waitForExistence(timeout: 5))
        app.buttons["moments-compose"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, text, "Closing the sheet must retain the failed draft")
        app.buttons["moment-publish"].tap()
        waitGone(draft)
        let published = app.staticTexts["moment-content-703"]
        reveal(published, in: app)
        XCTAssertEqual(published.label, text)
        capture("moments-night-retry-published-once")
        XCTAssertEqual(app.staticTexts.matching(identifier: "moment-content-703").count, 1)
        XCTAssertFalse(app.staticTexts["moment-content-704"].exists)
        app.terminate()
    }

    private func launch(skin: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-ui-test-moonlight",
                               "-ui-test-moments", "-app.skin", skin] + extra
        app.launch()
        XCTAssertTrue(app.buttons["tab-play"].waitForExistence(timeout: 12))
        return app
    }

    private func openMoments(_ app: XCUIApplication) {
        app.buttons["tab-play"].tap()
        let entry = app.buttons["play-moments"]
        reveal(entry, in: app)
        entry.tap()
        XCTAssertTrue(app.buttons["moments-compose"].waitForExistence(timeout: 8))
    }

    private enum Direction { case up, down }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, direction: Direction = .up) {
        _ = element.waitForExistence(timeout: 3)
        for _ in 0..<7 {
            if element.isHittable { break }
            let startY = direction == .up ? 0.78 : 0.35
            let endY = direction == .up ? 0.35 : 0.78
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.84, dy: startY))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.84, dy: endY)))
        }
        XCTAssertTrue(element.isHittable, "Could not reveal \(element.identifier)")
    }

    private func confirmDeletion(in app: XCUIApplication) {
        let confirm = app.buttons["删除"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
    }

    private func waitGone(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }

    private func waitValue(_ element: XCUIElement, equals value: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }

    private func waitLabel(_ element: XCUIElement, contains value: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; testCase.add(attachment)
    }
}
