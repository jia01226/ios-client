import XCTest

final class ThinkingInteractionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testThinkingExpandsAndCollapses() throws {
        let app = launch(arguments: ["-ui-test-thinking-static"])
        let open = app.buttons["查看思考"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["原文为英文"].exists)
        XCTAssertFalse(app.staticTexts["Hold her words first, then answer gently."].exists)
        attachScreenshot(named: "01-thinking-collapsed")

        open.tap()
        let sheet = app.descendants(matching: .any)["thinking-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 2))
        let body = app.staticTexts[
            "心口软了一下。她是在确认我还在不在，我不想让她落空。"
        ]
        XCTAssertTrue(body.waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Hold her words first, then answer gently."].exists)
        attachScreenshot(named: "02-thinking-expanded")

        app.buttons["完成"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 2))
        XCTAssertTrue(body.waitForNonExistence(timeout: 2))
        XCTAssertTrue(open.exists)
        attachScreenshot(named: "03-thinking-collapsed-again")
    }

    func testThinkingStaysExpandedWhileStreaming() throws {
        let app = launch(arguments: ["-ui-test-thinking-streaming"])
        let open = app.buttons["查看思考"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()

        let sheet = app.descendants(matching: .any)["thinking-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 2))
        attachScreenshot(named: "04-thinking-streaming-start")

        let finalThinking = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "心里那一下是真的软了。")
        ).firstMatch
        XCTAssertTrue(finalThinking.waitForExistence(timeout: 4))
        XCTAssertTrue(sheet.exists, "流式增量期间 Thinking 弹窗不应消失")
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

        let continueStream = app.buttons["继续测试流式回复"]
        XCTAssertTrue(continueStream.waitForExistence(timeout: 2))
        continueStream.tap()

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

    func testLongAssistantReplyWrapsAndUsesAvailableWidth() throws {
        let app = launch(arguments: ["-ui-test-long-reply"])
        let text = app.staticTexts[
            "这声倒是睡饱了的音儿。哭过、睡过、雨还在落，爸爸也在听雨。"
        ]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(text.frame.height, 30, "长回复必须换行显示，不能压成单行省略号")

        let bubble = app.descendants(matching: .any)
            .matching(identifier: "message-bubble-ui-test-long-assistant-0")
            .firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(
            bubble.frame.maxX,
            app.frame.maxX - 30,
            "换行的柯回复应铺到聊天区右边"
        )
        attachScreenshot(named: "07-long-reply-wraps-full-width")
    }

    func testLatestThinkingTitleDoesNotFlickerOrJump() throws {
        let app = launch(arguments: ["-ui-test-scroll-control"])
        let open = app.buttons["查看思考"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        let originalY = open.frame.minY

        open.tap()
        let sheet = app.descendants(matching: .any)["thinking-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 2))
        let sampledY = sampleVerticalPositions(of: sheet, duration: 1.1)

        XCTAssertLessThan(maximumDrift(in: sampledY), 3)
        app.buttons["完成"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 2))
        XCTAssertLessThan(abs(open.frame.minY - originalY), 3)
        attachScreenshot(named: "07-latest-thinking-stable")
    }

    func testThinkingKeepsItsAnchorWhileSplitBubblesArrive() throws {
        let app = launch(arguments: ["-ui-test-thinking-segment-race"])
        let open = app.buttons["查看思考"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        let originalY = open.frame.minY
        open.tap()

        let sheet = app.descendants(matching: .any)["thinking-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 2))
        let sampledY = sampleVerticalPositions(of: sheet, duration: 2.6)
        XCTAssertLessThan(maximumDrift(in: sampledY), 3)

        app.buttons["完成"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["第二条气泡随后出现。"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["第三条气泡最后出现。"].waitForExistence(timeout: 2))
        XCTAssertLessThan(abs(open.frame.minY - originalY), 3)
        attachScreenshot(named: "08-thinking-during-segmented-reply")
    }

    func testKeyboardFollowsLatestMessageAndDismisses() throws {
        let app = launch(arguments: ["-ui-test-scroll-control"])
        let latest = app.staticTexts["这是最新一条回复。"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        let restingY = latest.frame.minY
        let input = app.descendants(matching: .any)["chat-composer"]
        XCTAssertTrue(input.waitForExistence(timeout: 2))
        let tabBar = app.descendants(matching: .any)
            .matching(identifier: "root-tab-bar")
            .firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 2))
        XCTAssertLessThanOrEqual(input.frame.maxY, tabBar.frame.minY + 1)

        for cycle in 1...2 {
            input.tap()
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 2))
            XCTAssertTrue(tabBar.waitForNonExistence(timeout: 2))
            attachScreenshot(named: "09-keyboard-shown-\(cycle)")
            XCTAssertLessThan(latest.frame.maxY, keyboard.frame.minY)
            XCTAssertLessThanOrEqual(input.frame.maxY, keyboard.frame.minY + 1)

            latest.tap()
            XCTAssertTrue(keyboard.waitForNonExistence(timeout: 2))
            XCTAssertTrue(tabBar.waitForExistence(timeout: 2))
            XCTAssertTrue(latest.isHittable)
            XCTAssertLessThan(abs(latest.frame.minY - restingY), 3)
            XCTAssertLessThanOrEqual(input.frame.maxY, tabBar.frame.minY + 1)
            attachScreenshot(named: "10-keyboard-dismissed-\(cycle)")
        }
    }

    func testComposerReturnsFromHistoryToLatestMessage() throws {
        let app = launch(arguments: ["-ui-test-scroll-control"])
        let latest = app.staticTexts["这是最新一条回复。"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))

        let messageList = app.collectionViews["chat-timeline"]
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

    func testSendingKeepsKeyboardAndTimelineStable() throws {
        let app = launch(arguments: ["-ui-test-send-stability"])
        let previous = app.staticTexts["这是最新一条回复。"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))

        let input = app.descendants(matching: .any)["chat-composer"]
        XCTAssertTrue(input.waitForExistence(timeout: 2))
        input.tap()
        input.typeText("这条发出去别跳屏")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2))

        let send = app.buttons["send-message"]
        XCTAssertTrue(send.waitForExistence(timeout: 2))
        send.tap()

        let outgoing = app.staticTexts["这条发出去别跳屏"]
        XCTAssertTrue(outgoing.waitForExistence(timeout: 2))
        let reply = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "这次屏幕不会再乱跳。")
        ).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 4))
        XCTAssertTrue(keyboard.exists, "发送和流式回复期间键盘不应被列表刷新挤掉")
        XCTAssertLessThan(reply.frame.maxY, keyboard.frame.minY)

        let positions = sampleVerticalPositions(of: outgoing, duration: 0.8)
        XCTAssertLessThan(maximumDrift(in: positions), 3, "发送完成后自己的消息不应继续上下抖动")
        attachScreenshot(named: "13-send-keeps-timeline-stable")
    }

    func testSwitchingTabsPreservesChatInteractionState() throws {
        let app = launch(arguments: ["-ui-test-scroll-control"])
        let open = app.buttons["查看思考"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let sheet = app.descendants(matching: .any)["thinking-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 2))
        app.buttons["完成"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 2))

        app.buttons["我们"].tap()
        XCTAssertTrue(app.buttons["柯"].waitForExistence(timeout: 2))
        app.buttons["柯"].tap()

        XCTAssertTrue(
            open.waitForExistence(timeout: 2),
            "切 Tab 后 Thinking 入口不应消失"
        )
        XCTAssertTrue(app.staticTexts["这是最新一条回复。"].exists)
        attachScreenshot(named: "13-tab-return-preserves-chat")
    }

    func testRepeatedTabSwitchingNeverShowsBlankChat() throws {
        let app = launch(arguments: ["-ui-test-scroll-control"])
        let latest = app.staticTexts["这是最新一条回复。"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))

        let open = app.buttons["查看思考"]
        XCTAssertTrue(open.waitForExistence(timeout: 2))
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
                XCTAssertTrue(open.exists, "切 Tab 后 Thinking 入口不应丢失")
                XCTAssertTrue(latest.exists, "切 Tab 后最新消息数据不应丢失")
            }
        }

        XCTAssertLessThan(
            returnLatencies.max() ?? 0,
            1.2,
            "常驻聊天层返回后应在 1.2 秒内恢复可交互"
        )
        attachScreenshot(named: "14-repeated-tab-switching-stable")
    }

    func testModelFamiliesExpandCollapseAndSelectIndependently() throws {
        let app = launch(arguments: ["-ui-test-model-groups"])
        let settings = app.buttons["打开聊天设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.buttons["模型选择"].waitForExistence(timeout: 2))
        app.buttons["模型选择"].tap()

        for id in ["claude_1", "claude_2", "gpt", "deepseek"] {
            XCTAssertTrue(app.buttons["model-group-\(id)"].waitForExistence(timeout: 2))
        }
        let claude2 = app.buttons["model-group-claude_2"]
        let claude2Model = app.buttons["model-option-claude2-subscription-opus-5"]
        XCTAssertTrue(claude2Model.waitForExistence(timeout: 2), "当前模型所属分栏应默认展开")
        attachScreenshot(named: "15-model-groups-current-open")

        claude2.tap()
        XCTAssertTrue(claude2Model.waitForNonExistence(timeout: 2))

        let gpt = app.buttons["model-group-gpt"]
        gpt.tap()
        let gptModel = app.buttons["model-option-codex-subscription:gpt-5.6-terra"]
        XCTAssertTrue(gptModel.waitForExistence(timeout: 2))
        gptModel.tap()

        let summary = app.descendants(matching: .any)
            .matching(identifier: "selected-model-summary")
            .firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 2))
        XCTAssertTrue(summary.label.contains("GPT-5.6 Terra"))
        attachScreenshot(named: "16-model-groups-gpt-selected")

        gpt.tap()
        XCTAssertTrue(gptModel.waitForNonExistence(timeout: 2))
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
