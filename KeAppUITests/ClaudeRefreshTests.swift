import XCTest

final class ClaudeRefreshTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testClearWindowRemovesVisibleHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-model-groups"]
        app.launch()
        XCTAssertTrue(app.buttons["打开聊天设置"].waitForExistence(timeout: 5))
        app.buttons["打开聊天设置"].tap()
        let clear = app.buttons["clear-chat-window"]
        for _ in 0..<4 where !clear.isHittable { app.swipeUp() }
        XCTAssertTrue(clear.isHittable)
        clear.tap()
        XCTAssertTrue(app.staticTexts["当前聊天已清空，下一条从新的上下文开始。事实记忆保留。"].waitForExistence(timeout: 4))
        app.buttons["关闭聊天设置"].tap()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "message-bubble-ui-test-model-groups-message-0").firstMatch.exists)
    }

    func testRefreshKeepsMessagesAndExplainsNextReply() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-model-groups"]
        app.launch()
        XCTAssertTrue(app.buttons["打开聊天设置"].waitForExistence(timeout: 5))
        app.buttons["打开聊天设置"].tap()
        let refresh = app.buttons["refresh-claude-session"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 3))
        XCTAssertTrue(refresh.isEnabled)
        refresh.tap()
        XCTAssertTrue(app.staticTexts["下一条消息会用新的 Claude 会话。聊天记录和记忆都保留。"].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "claude-refresh-success"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["关闭聊天设置"].tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "message-bubble-ui-test-model-groups-message-0").firstMatch.exists)
    }

    func testRefreshDisabledWithoutClaudeSelection() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control"]
        app.launch()
        XCTAssertTrue(app.buttons["打开聊天设置"].waitForExistence(timeout: 5))
        app.buttons["打开聊天设置"].tap()
        let refresh = app.buttons["refresh-claude-session"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 3))
        XCTAssertFalse(refresh.isEnabled)
    }

    func testRefreshWithDarkAppearanceAndLargeText() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-model-groups", "-app.skin", "night",
                               "-AppleInterfaceStyle", "Dark",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["打开聊天设置"].waitForExistence(timeout: 5))
        app.buttons["打开聊天设置"].tap()
        let refresh = app.buttons["refresh-claude-session"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 3))
        XCTAssertTrue(refresh.isHittable)
        refresh.tap()
        XCTAssertTrue(app.staticTexts["下一条消息会用新的 Claude 会话。聊天记录和记忆都保留。"].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "claude-refresh-dark-large"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
