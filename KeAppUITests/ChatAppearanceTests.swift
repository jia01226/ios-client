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
