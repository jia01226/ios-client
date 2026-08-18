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

    func testLatestThinkingTitleDoesNotFlickerOrJump() throws {
        let app = launch(arguments: ["-ui-test-scroll-control"])
        let expand = app.buttons["展开思考"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        let originalY = expand.frame.minY

        expand.tap()
        let collapse = app.buttons["收起思考"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 2))
        let sampledY = sampleVerticalPositions(of: collapse, duration: 1.1)

        XCTAssertLessThan(maximumDrift(in: sampledY), 3)
        XCTAssertLessThan(abs((sampledY.last ?? originalY) - originalY), 3)
        attachScreenshot(named: "07-latest-thinking-stable")
    }

    func testThinkingKeepsItsAnchorWhileSplitBubblesArrive() throws {
        let app = launch(arguments: ["-ui-test-thinking-segment-race"])
        let expand = app.buttons["展开思考"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        expand.tap()

        let collapse = app.buttons["收起思考"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 2))
        let originalY = collapse.frame.minY
        XCTAssertTrue(app.staticTexts["第二条气泡随后出现。"].waitForExistence(timeout: 2))
        let afterSecondY = collapse.frame.minY
        XCTAssertTrue(app.staticTexts["第三条气泡最后出现。"].waitForExistence(timeout: 2))
        let afterThirdY = collapse.frame.minY

        XCTAssertLessThan(maximumDrift(in: [originalY, afterSecondY, afterThirdY]), 3)
        attachScreenshot(named: "08-thinking-during-segmented-reply")
    }

    func testKeyboardFollowsLatestMessageAndDismisses() throws {
        let app = launch(arguments: ["-ui-test-scroll-control"])
        let latest = app.staticTexts["这是最新一条回复。"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        let input = app.textFields["和柯说点什么…"]
        XCTAssertTrue(input.exists)

        input.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2))
        XCTAssertLessThan(latest.frame.maxY, keyboard.frame.minY)
        attachScreenshot(named: "09-keyboard-shown")

        latest.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 2))
        XCTAssertTrue(latest.isHittable)
        attachScreenshot(named: "10-keyboard-dismissed")
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

    private func sampleVerticalPositions(
        of element: XCUIElement,
        duration: TimeInterval
    ) -> [CGFloat] {
        let deadline = Date().addingTimeInterval(duration)
        var values: [CGFloat] = []
        while Date() < deadline {
            values.append(element.frame.minY)
            Thread.sleep(forTimeInterval: 0.08)
        }
        values.append(element.frame.minY)
        return values
    }

    private func maximumDrift(in values: [CGFloat]) -> CGFloat {
        guard let minimum = values.min(), let maximum = values.max() else { return 0 }
        return maximum - minimum
    }
}
