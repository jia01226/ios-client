import XCTest

final class ThinkingInteractionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testThinkingExpandsAndCollapses() throws {
        let app = launch(arguments: ["-ui-test-thinking-static"])
        let expand = app.buttons["展开思考"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["原文为英文"].exists)
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

    func testAssistantReplyStreamsIntoTheSameBubble() throws {
        let app = launch(arguments: ["-ui-test-reply-streaming"])
        let firstChunk = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "第一句先来到屏幕上，")
        ).firstMatch
        XCTAssertTrue(firstChunk.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "最后一句再慢慢说完。")
        ).firstMatch.exists, "正文第一段出现时，末段不应已经一次性显示")
        attachScreenshot(named: "06-reply-streaming-start")

        let completedReply = app.staticTexts.matching(
            NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@",
                "第一句先来到屏幕上，",
                "最后一句再慢慢说完。"
            )
        ).firstMatch
        XCTAssertTrue(completedReply.waitForExistence(timeout: 10))
        attachScreenshot(named: "07-reply-streaming-finished")
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
        let restingY = latest.frame.minY
        let input = app.descendants(matching: .any)["chat-composer"]
        XCTAssertTrue(input.waitForExistence(timeout: 2))

        for cycle in 1...2 {
            input.tap()
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 2))
            attachScreenshot(named: "09-keyboard-shown-\(cycle)")
            XCTAssertLessThan(latest.frame.maxY, keyboard.frame.minY)

            latest.tap()
            XCTAssertTrue(keyboard.waitForNonExistence(timeout: 2))
            XCTAssertTrue(latest.isHittable)
            XCTAssertLessThan(abs(latest.frame.minY - restingY), 3)
            attachScreenshot(named: "10-keyboard-dismissed-\(cycle)")
        }
    }

    func testComposerReturnsFromHistoryToLatestMessage() throws {
        let app = launch(arguments: ["-ui-test-scroll-control"])
        let latest = app.staticTexts["这是最新一条回复。"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))

        let messageList = app.scrollViews.firstMatch
        XCTAssertTrue(messageList.waitForExistence(timeout: 2))
        messageList.swipeDown(velocity: .fast)
        messageList.swipeDown(velocity: .fast)
        XCTAssertTrue(app.staticTexts["前面的消息 1"].isHittable)

        let input = app.descendants(matching: .any)["chat-composer"]
        input.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2))
        XCTAssertTrue(latest.waitForExistence(timeout: 2))
        XCTAssertTrue(latest.isHittable)
        XCTAssertLessThan(latest.frame.maxY, keyboard.frame.minY)
        attachScreenshot(named: "11-history-to-latest")
    }

    func testAttachmentTrayOverlaysWithoutMovingMessages() throws {
        let app = launch(arguments: [
            "-ui-test-scroll-control",
            "-ui-test-attachment-overlay"
        ])
        let latest = app.staticTexts["这是最新一条回复。"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        let originalY = latest.frame.minY

        let openAttachments = app.buttons["打开附件"]
        XCTAssertTrue(openAttachments.waitForExistence(timeout: 2))
        openAttachments.tap()
        let tray = app.descendants(matching: .any)["attachment-tray"]
        XCTAssertTrue(tray.waitForExistence(timeout: 2))
        XCTAssertLessThan(abs(latest.frame.minY - originalY), 3)
        XCTAssertLessThan(tray.frame.height, 240, "附件面板只应占按钮和一排缩略图的高度")
        attachScreenshot(named: "12-attachment-tray-overlay")
    }

    func testSwitchingTabsPreservesChatInteractionState() throws {
        let app = launch(arguments: ["-ui-test-scroll-control"])
        let expand = app.buttons["展开思考"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        expand.tap()
        XCTAssertTrue(app.buttons["收起思考"].waitForExistence(timeout: 2))

        app.buttons["我们"].tap()
        XCTAssertTrue(app.buttons["柯"].waitForExistence(timeout: 2))
        app.buttons["柯"].tap()

        XCTAssertTrue(
            app.buttons["收起思考"].waitForExistence(timeout: 2),
            "切 Tab 后聊天页不应被销毁重建"
        )
        XCTAssertTrue(app.staticTexts["这是最新一条回复。"].exists)
        attachScreenshot(named: "13-tab-return-preserves-chat")
    }

    func testRepeatedTabSwitchingNeverShowsBlankChat() throws {
        let app = launch(arguments: ["-ui-test-scroll-control"])
        let latest = app.staticTexts["这是最新一条回复。"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))

        let expand = app.buttons["展开思考"]
        XCTAssertTrue(expand.waitForExistence(timeout: 2))
        expand.tap()
        let collapse = app.buttons["收起思考"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 2))
        let composer = app.descendants(matching: .any)["chat-composer"]
        XCTAssertTrue(composer.exists && composer.isHittable)

        var returnLatencies: [TimeInterval] = []
        for cycle in 1...4 {
            for destination in ["我们", "玩", "回忆"] {
                let destinationButton = app.buttons[destination]
                XCTAssertTrue(destinationButton.exists)
                destinationButton.tap()

                let chatButton = app.buttons["柯"]
                XCTAssertTrue(chatButton.exists)
                let startedAt = Date()
                chatButton.tap()
                returnLatencies.append(Date().timeIntervalSince(startedAt))

                // tap() 返回时系统已经等到界面空闲；此刻同步检查比一秒轮询
                // 更严格，也不会把后续三次 XCTest 查询误算成 App 切页延迟。
                XCTAssertTrue(
                    composer.exists && composer.isHittable,
                    "第 \(cycle) 轮从 \(destination) 返回聊天时输入区不可交互"
                )
                XCTAssertTrue(collapse.exists, "切 Tab 后 Thinking 展开状态不应丢失")
                XCTAssertTrue(latest.exists, "切 Tab 后最新消息数据不应丢失")
            }
        }

        XCTAssertLessThan(
            returnLatencies.max() ?? 0,
            1,
            "常驻聊天层返回后应在一秒内恢复可交互"
        )
        attachScreenshot(named: "14-repeated-tab-switching-stable")
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
