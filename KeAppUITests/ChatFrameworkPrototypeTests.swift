import XCTest

final class ChatFrameworkPrototypeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testExyteThinkingAndStreamingKeepTheTitleStable() throws {
        let app = launchPrototype()
        let expand = app.buttons["展开原型思考"]
        XCTAssertTrue(expand.waitForExistence(timeout: 8))
        let originalY = expand.frame.minY

        expand.tap()
        let collapse = app.buttons["收起原型思考"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["先把她这句话接稳，再决定该怎样回答。"].exists)
        XCTAssertLessThan(abs(collapse.frame.minY - originalY), 3)

        app.buttons["继续原型流式回复"].tap()
        let streamed = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "最后一句在流式回复里继续长出来。")
        ).firstMatch
        XCTAssertTrue(streamed.waitForExistence(timeout: 4))
        XCTAssertLessThan(abs(collapse.frame.minY - originalY), 3)
        attachScreenshot(named: "framework-thinking-streaming")
    }

    func testExyteKeyboardKeepsLatestReplyVisible() throws {
        let app = launchPrototype()
        let latest = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "这是最新一条原型回复。")
        ).firstMatch
        XCTAssertTrue(latest.waitForExistence(timeout: 8))

        let composer = app.descendants(matching: .any)["framework-composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        composer.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        XCTAssertLessThan(latest.frame.maxY, keyboard.frame.minY)
        attachScreenshot(named: "framework-keyboard")
    }

    private func launchPrototype() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-chat-framework-prototype"]
        app.launch()
        return app
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
