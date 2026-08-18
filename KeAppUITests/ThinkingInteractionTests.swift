import XCTest

final class ThinkingInteractionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testThinkingExpandsAndCollapses() throws {
        let app = launch(arguments: ["-ui-test-thinking-static"])
        let expand = app.buttons["展开思考"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        attachScreenshot(named: "01-thinking-collapsed")

        expand.tap()
        let body = app.staticTexts[
            "先在心里把她这句话接住，再确认怎样回应才不会让她落空。"
        ]
        XCTAssertTrue(body.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["收起思考"].exists)
        attachScreenshot(named: "02-thinking-expanded")

        app.buttons["收起思考"].tap()
        XCTAssertTrue(body.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.buttons["展开思考"].exists)
        attachScreenshot(named: "03-thinking-collapsed-again")
    }

    func testThinkingStaysExpandedWhileStreaming() throws {
        let app = launch(arguments: ["-ui-test-thinking-streaming"])
        let expand = app.buttons["展开思考"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        expand.tap()

        let collapse = app.buttons["收起思考"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 2))
        attachScreenshot(named: "04-thinking-streaming-start")

        let finalThinking = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "最后确认每句话都只用中文。")
        ).firstMatch
        XCTAssertTrue(finalThinking.waitForExistence(timeout: 4))
        XCTAssertTrue(collapse.exists, "流式增量期间 Thinking 不应消失或自动折叠")
        attachScreenshot(named: "05-thinking-streaming-finished")
    }

    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
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
