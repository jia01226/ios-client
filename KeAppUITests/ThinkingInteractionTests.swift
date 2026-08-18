import XCTest

final class ThinkingInteractionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testThinkingExpandsAndCollapses() throws {
        let app = launch(arguments: ["-ui-test-thinking-static"])
        let expand = app.buttons["展开思考"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["原文为英文"].exists)
        XCTAssertFalse(app.staticTexts["Hold her words first, then answer gently."].exists)
        attachScreenshot(named: "01-thinking-collapsed")

        expand.tap()
        let body = app.staticTexts[
            "先在心里把她这句话接住，再确认怎样回应才不会让她落空。"
        ]
        XCTAssertTrue(body.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["收起思考"].exists)
        XCTAssertFalse(app.staticTexts["Hold her words first, then answer gently."].exists)
        attachScreenshot(named: "02-thinking-expanded")

        tapVisibleCenter(of: app.buttons["收起思考"], in: app)
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

    func testAssistantReplyAppearsAsSeparateBubbles() throws {
        let app = launch(arguments: ["-ui-test-segmented-reply"])
        XCTAssertTrue(app.staticTexts["第一句先接住你。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["第二句慢一点出来。"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["第三句最后跟上。"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts[
            "第一句先接住你。\n\n第二句慢一点出来。\n\n   \n第三句最后跟上。"
        ].exists)
        attachScreenshot(named: "06-segmented-reply")
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

    private func tapVisibleCenter(of element: XCUIElement, in app: XCUIApplication) {
        let frame = element.frame
        XCTAssertFalse(frame.isEmpty)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            .tap()
    }
}
