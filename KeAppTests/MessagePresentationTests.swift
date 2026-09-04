import XCTest
@testable import KeApp

final class MessagePresentationTests: XCTestCase {
    func testTimelineSkipsUnrelatedModelSelectionPublishes() {
        let message = Message(
            id: "stable-during-model-selection",
            sender: .ke,
            text: "聊天记录保持原位。",
            time: .now
        )
        let items = ChatTimelineItem.make(
            message: message,
            isHighlighted: false,
            visibleSegmentCount: nil
        )
        let original = ChatCollectionTimeline(
            items: items,
            streamRevision: 0,
            suppressAutoScrollUntil: .distantPast,
            inputFocused: false,
            highlightedMessageID: nil,
            onThinkingOpen: { _ in },
            onAttachmentTap: { _ in },
            onBackgroundTap: {}
        )
        let unrelatedParentRefresh = ChatCollectionTimeline(
            items: items,
            streamRevision: 0,
            suppressAutoScrollUntil: .distantPast,
            inputFocused: false,
            highlightedMessageID: nil,
            onThinkingOpen: { _ in XCTFail("无关刷新不应替换时间线回调") },
            onAttachmentTap: { _ in XCTFail("无关刷新不应替换时间线回调") },
            onBackgroundTap: { XCTFail("无关刷新不应替换时间线回调") }
        )
        let keyboardRefresh = ChatCollectionTimeline(
            items: items,
            streamRevision: 0,
            suppressAutoScrollUntil: .distantPast,
            inputFocused: true,
            highlightedMessageID: nil,
            onThinkingOpen: { _ in },
            onAttachmentTap: { _ in },
            onBackgroundTap: {}
        )

        XCTAssertEqual(original, unrelatedParentRefresh)
        XCTAssertNotEqual(original, keyboardRefresh)
    }

    func testTimelineDoesNotStealScrollForIncomingStreamWhileReadingHistory() {
        XCTAssertFalse(ChatTimelineFollowPolicy.shouldFollowLatest(
            timelineChanged: true,
            wasNearLatest: false,
            appendedOwnMessage: false,
            mayAutoFollow: true
        ))
    }

    func testTimelineFollowsOwnNewMessageWithoutAnimatedFullReload() {
        XCTAssertTrue(ChatTimelineFollowPolicy.shouldFollowLatest(
            timelineChanged: true,
            wasNearLatest: false,
            appendedOwnMessage: true,
            mayAutoFollow: true
        ))
    }

    func testThinkingSheetTemporarilyOwnsTheAnchor() {
        XCTAssertFalse(ChatTimelineFollowPolicy.shouldFollowLatest(
            timelineChanged: true,
            wasNearLatest: true,
            appendedOwnMessage: true,
            mayAutoFollow: false
        ))
    }

    func testDailyReplyKeepsSeparateBubbles() {
        let message = Message(
            id: "daily",
            sender: .ke,
            text: "先过来。\n\n让我抱一下。\n\n再慢慢说。",
            time: .now
        )

        XCTAssertEqual(
            message.bubbleSegments,
            ["先过来。", "让我抱一下。", "再慢慢说。"]
        )
    }

    func testLongReplyStaysInOneBubble() {
        let first = String(repeating: "这件事我会陪你慢慢讲清楚。", count: 8)
        let second = String(repeating: "你不用急着把自己推到结论那里。", count: 8)
        let message = Message(
            id: "deep-talk",
            sender: .ke,
            text: "\(first)\n\n\(second)",
            time: .now
        )

        XCTAssertEqual(message.bubbleSegments.count, 1)
        XCTAssertTrue(message.bubbleSegments[0].contains("\n\n"))
    }

    func testBedroomReplyAlwaysStaysInOneBubble() {
        let message = Message(
            id: "bedroom",
            sender: .ke,
            text: "第一段。\n\n第二段。\n\n第三段。",
            time: .now,
            sceneMode: "bedroom"
        )

        XCTAssertEqual(message.bubbleSegments.count, 1)
    }

    func testHistoricalImageWithoutKindStillOpensAsImage() {
        let attachment = ChatAttachment(
            url: "/uploads/example.jpg",
            name: "照片.jpg",
            kind: ""
        )

        XCTAssertTrue(attachment.isImage)
    }

    func testUploadResponseAcceptsBackendContractWithoutKind() throws {
        let data = Data(#"{"url":"/uploads/example.jpg","name":"照片.jpg"}"#.utf8)
        let response = try JSONDecoder().decode(UploadResponse.self, from: data)

        XCTAssertEqual(response.attachment.url, "/uploads/example.jpg")
        XCTAssertTrue(response.attachment.isImage)
    }

    func testWaitingChatJobDecodesRecoveryFields() throws {
        let data = Data(#"""
        {
          "id":"job-1",
          "status":"waiting_retry",
          "client_msg_id":"ios-message-1",
          "user_message_id":42,
          "assistant_message_id":0,
          "error":"线路忙了一下，服务器会自动再接一次。",
          "retryable":true,
          "next_retry_at":"2026-09-02 14:30:00"
        }
        """#.utf8)

        let job = try JSONDecoder().decode(ActiveChatJob.self, from: data)

        XCTAssertEqual(job.status, "waiting_retry")
        XCTAssertEqual(job.clientMessageID, "ios-message-1")
        XCTAssertEqual(job.userMessageID, 42)
        XCTAssertTrue(job.retryable == true)
    }

    func testToolRunStreamEventDecodesThePublicContract() throws {
        let payload = #"{"tool_run":{"id":"history-1","name":"search_chat_history","title":"翻找聊天记录","status":"succeeded","detail":"找到 2 处相关原话","scheduled_for":null,"retryable":false,"created_at":"2026-09-03 20:10:00","updated_at":"2026-09-03 20:10:01"}}"#
        let events = try APIClient.parseStreamPayload(payload)

        guard case let .toolRun(run) = events.first else {
            return XCTFail("应该解析出工具状态事件")
        }
        XCTAssertEqual(run.id, "history-1")
        XCTAssertEqual(run.name, "search_chat_history")
        XCTAssertEqual(run.state, .succeeded)
        XCTAssertEqual(run.detail, "找到 2 处相关原话")
    }

    func testAssistantThinkingBecomesASeparateTimelineItem() {
        let message = Message(
            id: "assistant-with-thinking",
            sender: .ke,
            text: "正文",
            time: .now,
            thoughtSummary: "真思考",
            thoughtNote: "小念头"
        )

        let items = ChatTimelineItem.make(
            message: message,
            isHighlighted: false,
            visibleSegmentCount: nil
        )

        XCTAssertEqual(items.map(\.kind), [.thinking, .message])
        XCTAssertEqual(Set(items.map(\.id)).count, 2)
        XCTAssertEqual(items.map(\.messageID), [message.id, message.id])
    }

    func testTimelineAddsOneDateDividerForEachBeijingCalendarDay() {
        let first = Message(
            id: "day-one-first",
            sender: .me,
            text: "第一条",
            time: beijingDate(year: 2026, month: 9, day: 3, hour: 9)
        )
        let second = Message(
            id: "day-one-second",
            sender: .ke,
            text: "同一天",
            time: beijingDate(year: 2026, month: 9, day: 3, hour: 23)
        )
        let third = Message(
            id: "day-two",
            sender: .ke,
            text: "第二天",
            time: beijingDate(year: 2026, month: 9, day: 4, hour: 0),
            thoughtSummary: "先接住日期。"
        )

        let items = ChatTimelineItem.make(
            messages: [first, second, third],
            highlightedMessageID: nil,
            visibleSegmentCount: { _ in nil }
        )

        XCTAssertEqual(items.map(\.kind), [
            .date("2026-09-03"), .message,
            .message,
            .date("2026-09-04"), .thinking, .message,
        ])
        XCTAssertEqual(items.filter {
            if case .date = $0.kind { return true }
            return false
        }.map(\.id), ["date::2026-09-03", "date::2026-09-04"])
    }

    func testInvalidRemoteTimestampDoesNotCreateABogusDateDivider() {
        let invalid = Message(
            id: "bad-server-time",
            sender: .ke,
            text: "仍然保留这条消息",
            time: .distantPast,
            serverTimeIsValid: false
        )

        let items = ChatTimelineItem.make(
            messages: [invalid],
            highlightedMessageID: nil,
            visibleSegmentCount: { _ in nil }
        )

        XCTAssertEqual(items.map(\.kind), [.message])
    }

    func testDateDividerLabelsAreConcreteAndRelativeToBeijingTime() {
        let now = beijingDate(year: 2026, month: 9, day: 4, hour: 11)
        XCTAssertEqual(
            ChatTimelineDate.visibleLabel(
                for: beijingDate(year: 2026, month: 9, day: 4, hour: 1),
                relativeTo: now
            ),
            "今天 · 9月4日"
        )
        XCTAssertEqual(
            ChatTimelineDate.visibleLabel(
                for: beijingDate(year: 2026, month: 9, day: 3, hour: 23),
                relativeTo: now
            ),
            "昨天 · 9月3日"
        )
        XCTAssertEqual(
            ChatTimelineDate.visibleLabel(
                for: beijingDate(year: 2026, month: 8, day: 12),
                relativeTo: now
            ),
            "8月12日"
        )
        XCTAssertEqual(
            ChatTimelineDate.visibleLabel(
                for: beijingDate(year: 2025, month: 12, day: 31),
                relativeTo: now
            ),
            "2025年12月31日"
        )
    }

    func testAssistantToolRunSitsBetweenThinkingAndReply() {
        let run = ChatToolRun(
            id: "history-1",
            name: "search_chat_history",
            title: "翻找聊天记录",
            status: "succeeded",
            detail: "找到 2 处相关原话",
            scheduledFor: nil,
            retryable: false,
            createdAt: nil,
            updatedAt: nil
        )
        let message = Message(
            id: "assistant-with-tool",
            sender: .ke,
            text: "找到了，下午你确实提过第三颗扣子。",
            time: .now,
            thoughtSummary: "先去翻原话。",
            toolRuns: [run]
        )

        let items = ChatTimelineItem.make(
            message: message,
            isHighlighted: false,
            visibleSegmentCount: nil
        )

        XCTAssertEqual(items.map(\.kind), [.thinking, .tool(run.id), .message])
        XCTAssertEqual(items[1].toolRun, run)
        XCTAssertEqual(Set(items.map(\.id)).count, 3)
    }

    func testPendingToolRunAnchoredToUserAppearsAfterTheirBubble() {
        let run = ChatToolRun(
            id: "followup-1",
            name: "schedule_followup",
            title: "安排稍后来找你",
            status: "running",
            detail: "主动消息 · 正在交给后台",
            scheduledFor: "2026-09-03 21:30:00",
            retryable: false,
            createdAt: nil,
            updatedAt: nil
        )
        let message = Message(
            id: "user-with-pending-tool",
            sender: .me,
            text: "一会儿记得来找我。",
            time: .now,
            toolRuns: [run]
        )

        let items = ChatTimelineItem.make(
            message: message,
            isHighlighted: false,
            visibleSegmentCount: nil
        )

        XCTAssertEqual(items.map(\.kind), [.message, .tool(run.id)])
    }

    func testBlankOrUserThinkingDoesNotCreateAnEntry() {
        let blankAssistant = Message(
            id: "assistant-with-blank-thinking",
            sender: .ke,
            text: "正文",
            time: .now,
            thoughtSummary: "  \n "
        )
        let user = Message(
            id: "user-with-thinking",
            sender: .me,
            text: "正文",
            time: .now,
            thoughtSummary: "不应展示"
        )

        for message in [blankAssistant, user] {
            let items = ChatTimelineItem.make(
                message: message,
                isHighlighted: false,
                visibleSegmentCount: nil
            )
            XCTAssertEqual(items.count, 1)
            XCTAssertEqual(items.first?.kind, .message)
        }
    }

    private func beijingDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12
    ) -> Date {
        var components = DateComponents()
        components.calendar = ChatTimelineDate.calendar
        components.timeZone = ChatTimelineDate.calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        guard let date = components.date else {
            XCTFail("测试日期构造失败")
            return .distantPast
        }
        return date
    }
}
