import XCTest

final class ChatAppearanceTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAppearanceSettingsCoverChatAndChoicesReturnToChat() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control"]
        app.launch()
        XCTAssertTrue(app.buttons["打开聊天设置"].waitForExistence(timeout: 5))
        app.buttons["打开聊天设置"].tap()
        let bar = app.descendants(matching: .any).matching(identifier: "root-tab-bar").firstMatch
        XCTAssertFalse(bar.isHittable)
        app.buttons["聊天配色"].tap()
        XCTAssertTrue(app.buttons["焦糖玫瑰"].waitForExistence(timeout: 3))
        app.buttons["焦糖玫瑰"].tap()
        XCTAssertFalse(app.staticTexts["鼠尾草"].exists)
        app.buttons["返回聊天设置"].tap()
        app.buttons["聊天字体"].tap()
        XCTAssertTrue(app.buttons["霞鹜文楷"].waitForExistence(timeout: 3))
        app.buttons["霞鹜文楷"].tap()
        app.buttons["苹方 · 常规"].tap()
        app.buttons["返回聊天设置"].tap()
        app.buttons["关闭聊天设置"].tap()
        XCTAssertTrue(app.textFields["chat-composer"].waitForExistence(timeout: 3))
        XCTAssertTrue(bar.isHittable)
        XCTAssertTrue(app.buttons["复制消息"].firstMatch.isHittable)
    }
    func testLongPressKeepsMessageInPlaceAndCopies() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control"]
        app.launch()
        let message = app.staticTexts["这是最新一条回复。"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        let originalY = message.frame.minY
        message.press(forDuration: 0.7)
        let copy = app.buttons["message-action-copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 3))
        XCTAssertLessThan(abs(message.frame.minY - originalY), 3)
        copy.tap()
        XCTAssertTrue(copy.waitForNonExistence(timeout: 3))
        XCTAssertLessThan(abs(message.frame.minY - originalY), 3)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "long-press-dismissed-stable"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLongPressWithKeyboardAndRecallCancellation() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control"]
        app.launch()
        let input = app.textFields["chat-composer"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let message = app.staticTexts["这是最新一条回复。"]
        let originalY = message.frame.minY
        message.press(forDuration: 0.7)
        let copy = app.buttons["message-action-copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 3))
        XCTAssertLessThan(abs(message.frame.minY - originalY), 3)
        copy.tap()
        XCTAssertLessThan(abs(message.frame.minY - originalY), 3)
        let ownMessage = app.staticTexts["前面的消息 7"]
        XCTAssertTrue(ownMessage.isHittable)
        ownMessage.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["撤回"].waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "message-actions-anchored"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["撤回"].tap()
        XCTAssertTrue(app.buttons["撤回消息"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
        XCTAssertTrue(ownMessage.exists)
    }

    func testQuoteSelectionOpensSheetWithoutSendingChat() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control"]
        app.launch()
        let message = app.staticTexts["这是最新一条回复。"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        message.press(forDuration: 0.7)
        let action = app.buttons["message-action-save-quote"]
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        action.tap()
        XCTAssertTrue(app.buttons["收下"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["哪里像柯？可以留空"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "app-quote-save"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.textFields["chat-composer"].waitForExistence(timeout: 3))
    }

    func testDateSearchPreservesTimeAndReturnsToMatchingMessage() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control"]
        app.launch()
        XCTAssertTrue(app.buttons["打开聊天设置"].waitForExistence(timeout: 5))
        app.buttons["打开聊天设置"].tap()
        app.buttons["按日期查找"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chat-date-picker").firstMatch.waitForExistence(timeout: 3))
        let result = app.buttons.containing(.staticText, identifier: "这是最新一条回复。").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        result.tap()
        XCTAssertTrue(app.buttons["打开聊天设置"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["这是最新一条回复。"].exists)
    }

}
