import XCTest
import UIKit
@testable import KeApp

final class MessagePresentationTests: XCTestCase {
    func testDefaultChatAndAllPagesShareOneMorandiPalette() throws {
        // 126：默认换成「粉白」排第一；月光浅粉还在，取值不变
        XCTAssertEqual(ChatPalette.all.first?.id, ChatPalette.blushID)
        let palette = try XCTUnwrap(ChatPalette.all.first { $0.id == "moonlight-pink" })
        XCTAssertEqual(palette.base, Morandi.background)
        XCTAssertEqual(palette.ink, Morandi.ink)
        XCTAssertEqual(palette.accent, Morandi.rose)
        XCTAssertEqual(palette.reply, Morandi.reply)
    }

    // 126：时间线铺满整屏，上下留白 = 让过顶上浮栏、让过输入胶囊（含底栏和 Home 条）
    func testTimelineInsetsClearFloatingChrome() {
        let full = CGRect(x: 0, y: 0, width: 390, height: 844)
        let insets = ChatCollectionTimelineController.chromeInsets(timelineFrame: full, chromeTop: 127, chromeBottom: 690)
        XCTAssertEqual(insets.top, 127)
        XCTAssertEqual(insets.bottom, 154)
        // 键盘起来：时间线只到键盘上沿，输入胶囊贴着键盘，底下只让输入胶囊那一截
        let shrunk = CGRect(x: 0, y: 0, width: 390, height: 508)
        let keyboard = ChatCollectionTimelineController.chromeInsets(timelineFrame: shrunk, chromeTop: 127, chromeBottom: 446)
        XCTAssertEqual(keyboard.bottom, 62)
        // 浮栏量出来比时间线还靠外（还没量好）时不给负的
        let none = ChatCollectionTimelineController.chromeInsets(timelineFrame: full, chromeTop: -10, chromeBottom: 900)
        XCTAssertEqual(none, .zero)
    }

    func testPinkPaletteUsesJReplyColorWithoutChangingMyBubbleColor() {
        let palette = try! XCTUnwrap(ChatPalette.all.first { $0.id == "pink" })

        XCTAssertEqual(palette.reply, 0xF5E4E7)
        XCTAssertEqual(palette.tint, 0xE6C6D0)
    }

    func testSendFeedbackRequiresServerReceiptAndDoesNotRepeatOnRetry() {
        var gate = SendReceiptFeedbackGate()
        XCTAssertFalse(gate.consume(clientID: "a", serverID: nil))
        XCTAssertTrue(gate.consume(clientID: "a", serverID: 7))
        XCTAssertFalse(gate.consume(clientID: "a", serverID: 7))
        XCTAssertTrue(gate.consume(clientID: "b", serverID: 8))
    }

    func testRecallOnlyAllowsOwnPersistedSentMessages() {
        var own = Message(id: "own", serverID: 7, sender: .me, text: "sample", time: .now)
        XCTAssertTrue(own.canRecall)
        own.deliveryState = .sending
        XCTAssertFalse(own.canRecall)
        own.deliveryState = .sent
        own.serverID = nil
        XCTAssertFalse(own.canRecall)
        let reply = Message(id: "reply", serverID: 8, sender: .ke, text: "sample", time: .now)
        XCTAssertFalse(reply.canRecall)
    }

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
            scrollToLatestRequest: 0,
            onThinkingOpen: { _ in },
            onAttachmentTap: { _ in },
            onBackgroundTap: {},
            onScrollToLatestVisibilityChanged: { _ in }
        )
        let unrelatedParentRefresh = ChatCollectionTimeline(
            items: items,
            streamRevision: 0,
            suppressAutoScrollUntil: .distantPast,
            inputFocused: false,
            highlightedMessageID: nil,
            scrollToLatestRequest: 0,
            onThinkingOpen: { _ in XCTFail("无关刷新不应替换时间线回调") },
            onAttachmentTap: { _ in XCTFail("无关刷新不应替换时间线回调") },
            onBackgroundTap: { XCTFail("无关刷新不应替换时间线回调") },
            onScrollToLatestVisibilityChanged: { _ in
                XCTFail("无关刷新不应替换时间线回调")
            }
        )
        let keyboardRefresh = ChatCollectionTimeline(
            items: items,
            streamRevision: 0,
            suppressAutoScrollUntil: .distantPast,
            inputFocused: true,
            highlightedMessageID: nil,
            scrollToLatestRequest: 0,
            onThinkingOpen: { _ in },
            onAttachmentTap: { _ in },
            onBackgroundTap: {},
            onScrollToLatestVisibilityChanged: { _ in }
        )

        XCTAssertEqual(original, unrelatedParentRefresh)
        XCTAssertNotEqual(original, keyboardRefresh)
    }

    func testTimelineDoesNotStealScrollForIncomingStreamWhileReadingHistory() {
        XCTAssertFalse(ChatTimelineFollowPolicy.shouldFollowLatest(
            timelineChanged: true,
            wasFollowingLatest: false,
            appendedOwnMessage: false,
            mayAutoFollow: true
        ))
    }

    func testTimelineFollowsOwnNewMessageWithoutAnimatedFullReload() {
        XCTAssertTrue(ChatTimelineFollowPolicy.shouldFollowLatest(
            timelineChanged: true,
            wasFollowingLatest: false,
            appendedOwnMessage: true,
            mayAutoFollow: true
        ))
    }

    func testThinkingSheetTemporarilyOwnsTheAnchor() {
        XCTAssertFalse(ChatTimelineFollowPolicy.shouldFollowLatest(
            timelineChanged: true,
            wasFollowingLatest: true,
            appendedOwnMessage: true,
            mayAutoFollow: false
        ))
    }

    func testTimelineKeepsFollowingDuringTransientSelfSizingDrift() {
        XCTAssertTrue(ChatTimelineFollowPolicy.shouldFollowLatest(
            timelineChanged: true,
            wasFollowingLatest: true,
            appendedOwnMessage: false,
            mayAutoFollow: true
        ))
    }

    func testScrollToLatestControlOnlyAppearsAfterLeavingBottomArea() {
        XCTAssertFalse(ChatTimelineScrollControlPolicy.shouldShow(
            distanceFromLatest: 95,
            revealDistance: 96
        ))
        XCTAssertTrue(ChatTimelineScrollControlPolicy.shouldShow(
            distanceFromLatest: 97,
            revealDistance: 96
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

    /// 120：柯开锁日记那条：认得出是哪一篇、整条不切；普通附件、她发的、老消息都照旧。
    func testDiaryUnlockMessageIsOneCardPointingAtTheEntry() {
        let key = ChatAttachment(url: "ke-diary://42", name: "下雨那天", kind: "diary")
        let unlock = Message(id: "unlock", serverID: 9, sender: .ke, text: "爸爸开锁了：「下雨那天」\n\n多一段", time: .now, attachments: [key])
        XCTAssertEqual(unlock.unlockedDiary?.diaryID, 42)
        XCTAssertEqual(unlock.bubbleSegments.count, 1)

        let photo = ChatAttachment(url: "/uploads/example.jpg", name: "照片.jpg", kind: "image")
        XCTAssertNil(photo.diaryID)
        XCTAssertNil(ChatAttachment(url: "ke-diary://42", name: "下雨那天", kind: "file").diaryID)
        XCTAssertNil(ChatAttachment(url: "/uploads/42", name: "下雨那天", kind: "diary").diaryID)
        let old = Message(id: "old", sender: .ke, text: "先过来。\n\n再慢慢说。", time: .now, attachments: [photo])
        XCTAssertNil(old.unlockedDiary)
        XCTAssertEqual(old.bubbleSegments, ["先过来。", "再慢慢说。"])
        XCTAssertNil(Message(id: "mine", sender: .me, text: "", time: .now, attachments: [key]).unlockedDiary)
    }

    // MARK: 121 后台切好的气泡

    /// 121：服务器切好的为准；本机切法只给没带 segments 的旧缓存
    func testServerSegmentsArePreferredOverLocalSplit() {
        let server = Message(id: "server", serverID: 1, sender: .ke, text: "先过来。\n\n让我抱一下。\n\n再慢慢说。",
                             time: .now, segments: ["先过来。\n\n让我抱一下。", "再慢慢说。"])
        XCTAssertEqual(server.bubbleSegments, ["先过来。\n\n让我抱一下。", "再慢慢说。"])

        // 卧室里本机会整段不切；服务器说切就切（规则只在服务器一处定）
        let bedroom = Message(id: "bedroom", serverID: 2, sender: .ke, text: "一。\n\n二。", time: .now,
                              sceneMode: "bedroom", segments: ["一。", "二。"])
        XCTAssertEqual(bedroom.bubbleSegments, ["一。", "二。"])

        // 空的、全是空白的服务器切法当没有，退回本机切法
        let blank = Message(id: "blank", serverID: 3, sender: .ke, text: "先过来。\n\n再慢慢说。", time: .now,
                            segments: ["  ", ""])
        XCTAssertEqual(blank.bubbleSegments, ["先过来。", "再慢慢说。"])
        let oldCache = Message(id: "old", serverID: 4, sender: .ke, text: "先过来。\n\n再慢慢说。", time: .now)
        XCTAssertEqual(oldCache.bubbleSegments, ["先过来。", "再慢慢说。"])

        // 她的话不按柯的切法走
        let mine = Message(id: "mine", sender: .me, text: "一。\n\n二。", time: .now, segments: ["一。", "二。"])
        XCTAssertEqual(mine.bubbleSegments, ["一。\n\n二。"])
    }

    /// 121：还在写的那条一个气泡都不出，时间线里只剩一行（时间和「发送中」）
    func testStreamingReplyRendersNoTextSegments() {
        let streaming = Message(id: "streaming", sender: .ke, text: "半截的正文\n\n还在长", time: .now,
                                thoughtSummary: "先想一想。", segments: ["半截的正文", "还在长"],
                                isStreaming: true, deliveryState: .sending)
        XCTAssertEqual(streaming.bubbleSegments, [])
        XCTAssertTrue(Message(id: "placeholder", sender: .ke, text: "", time: .now,
                              isStreaming: true, deliveryState: .sending).isAwaitingReply)

        let items = ChatTimelineItem.make(message: streaming, isHighlighted: false, visibleSegmentCount: nil)
        XCTAssertEqual(items.map(\.kind), [.thinking, .message], "Thinking 照常在，正文那一行没有字")
        XCTAssertEqual(items.last?.part, ChatBubblePart(index: 0, count: 1, text: nil))
    }

    /// 121：一个个冒出来就是一行行插进来；已经冒出来的那几行不重画、不变
    func testRevealInsertsBubbleRowsWithoutTouchingVisibleOnes() throws {
        let reply = Message(id: "reply", serverID: 7, sender: .ke, text: "一。\n\n二。\n\n三。", time: .now,
                            thoughtSummary: "想好了。", segments: ["一。", "二。", "三。"])
        let first = ChatTimelineItem.make(messages: [reply], highlightedMessageID: nil, visibleSegmentCount: { _ in 1 })
        let second = ChatTimelineItem.make(messages: [reply], highlightedMessageID: nil, visibleSegmentCount: { _ in 2 })
        let all = ChatTimelineItem.make(messages: [reply], highlightedMessageID: nil, visibleSegmentCount: { _ in nil })

        XCTAssertEqual(first.filter { $0.part != nil }.map(\.kind), [.message])
        XCTAssertEqual(all.filter { $0.part != nil }.map(\.kind), [.message, .segment(1), .segment(2)])
        XCTAssertEqual(all.compactMap(\.part?.text), ["一。", "二。", "三。"])
        XCTAssertEqual(all.compactMap(\.part).map(\.isLast), [false, false, true], "时间只跟在最后一个气泡下面")
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)

        let step = try XCTUnwrap(ChatTimelineChanges.between(first, second))
        XCTAssertEqual(step.inserted, [first.count])
        XCTAssertEqual(step.reloaded, [], "第一个气泡原样不动")
        XCTAssertEqual(step.deleted, [])
        let rest = try XCTUnwrap(ChatTimelineChanges.between(second, all))
        XCTAssertEqual(rest, ChatTimelineChanges(inserted: [second.count]))
    }

    /// 121：本机那条换成服务器那条（沿用本机 id）时，气泡一样就一格都不重画、不重新冒
    func testHistoryHandoverWithIdenticalSegmentsReloadsNothing() throws {
        let sentAt = beijingDate(year: 2026, month: 10, day: 19, hour: 21)
        let local = Message(id: "assistant-ios-1", serverID: 101, clientID: "ios-1", sender: .ke,
                            text: "先过来。\n\n再慢慢说。", time: sentAt, thoughtSummary: "想好了。",
                            segments: ["先过来。", "再慢慢说。"])
        var remote = Message(id: "assistant-ios-1", serverID: 101, sender: .ke,
                             text: "先过来。\n\n再慢慢说。\n", time: sentAt.addingTimeInterval(4),
                             serverTimeIsValid: true, thoughtSummary: "想好了。",
                             thoughtSummaryRaw: "Ready.", sceneMode: "daily", attachments: [],
                             segments: ["先过来。", "再慢慢说。"])
        let before = ChatTimelineItem.make(messages: [local], highlightedMessageID: nil, visibleSegmentCount: { _ in nil })
        var after = ChatTimelineItem.make(messages: [remote], highlightedMessageID: nil, visibleSegmentCount: { _ in nil })
        XCTAssertEqual(before, after)
        XCTAssertEqual(ChatTimelineChanges.between(before, after), ChatTimelineChanges())

        // 服务器切法真的不一样了，才重画那一格
        remote.segments = ["先过来。", "再慢慢说吧。"]
        after = ChatTimelineItem.make(messages: [remote], highlightedMessageID: nil, visibleSegmentCount: { _ in nil })
        let changed = try XCTUnwrap(ChatTimelineChanges.between(before, after))
        XCTAssertEqual(changed.reloaded, [after.count - 1])
        XCTAssertEqual(changed.inserted, [])
    }

    /// 121：占位换成第一个气泡、后面的气泡同时插进来（减弱动态效果时）：占位那格不能漏掉。顺序乱了才整页重载。
    /// 125：占位那一行不在原位重画，而是删掉、插进第一个气泡——不会留下「等待接回」那一格。
    func testLandingReplacesThePlaceholderRowAndInsertsTheRest() throws {
        let mine = Message(id: "user-ios-1", serverID: 100, sender: .me, text: "在吗", time: .now)
        var reply = Message(id: "assistant-ios-1", clientID: "ios-1", sender: .ke, text: "", time: .now,
                            isStreaming: true, deliveryState: .sending)
        let waiting = ChatTimelineItem.make(messages: [mine, reply], highlightedMessageID: nil, visibleSegmentCount: { _ in nil })
        reply.serverID = 101
        reply.text = "在。\n\n一直在。"
        reply.segments = ["在。", "一直在。"]
        reply.isStreaming = false
        reply.deliveryState = .sent
        let landed = ChatTimelineItem.make(messages: [mine, reply], highlightedMessageID: nil, visibleSegmentCount: { _ in nil })

        let changes = try XCTUnwrap(ChatTimelineChanges.between(waiting, landed))
        XCTAssertEqual(changes.deleted, [waiting.count - 1], "占位那一行删掉")
        XCTAssertEqual(changes.inserted, [landed.count - 2, landed.count - 1], "两个气泡都是新插进来的")
        XCTAssertEqual(changes.reloaded, [])
        XCTAssertEqual(landed[landed.count - 2].part?.text, "在。")

        XCTAssertNil(ChatTimelineChanges.between(landed, Array(landed.reversed())))
    }

    /// 125（她的截图，7145）：流在回执后就断了，Thinking 和五段都是拉记录才带来的。落下来时上面插进 Thinking、
    /// 下面是第一句：「等待接回」那一格必须没了，第一行就是「过来」；时间线不在原位重画任何一格。
    func testLandingWithThinkingFromHistoryLeavesNoWaitingRowBehind() throws {
        let mine = Message(id: "user-ios-1", serverID: 7144, sender: .me, text: "我是不是想错了", time: .now)
        var reply = Message(id: "assistant-ios-1", clientID: "ios-1", sender: .ke, text: "", time: .now,
                            isStreaming: true, deliveryState: .waiting)
        let waiting = ChatTimelineItem.make(messages: [mine, reply], highlightedMessageID: nil, visibleSegmentCount: { _ in nil })
        XCTAssertEqual(waiting.last?.id, "assistant-ios-1::awaiting")
        let segments = ["过来", "你想法没有不对…", "控制不住也不是你的问题…", "休假是在治病…", "现在头搁爸爸肩上…"]
        reply.serverID = 7145
        reply.text = segments.joined(separator: "\n\n")
        reply.segments = segments
        reply.thoughtSummary = "她在怪自己。"
        reply.isStreaming = false
        reply.deliveryState = .sent
        let landed = ChatTimelineItem.make(messages: [mine, reply], highlightedMessageID: nil, visibleSegmentCount: { _ in 1 })

        XCTAssertFalse(landed.contains { $0.id.hasSuffix("::awaiting") })
        XCTAssertEqual(landed.suffix(2).map(\.kind), [.thinking, .message])
        XCTAssertEqual(landed.last?.part?.text, "过来")
        let changes = try XCTUnwrap(ChatTimelineChanges.between(waiting, landed))
        XCTAssertEqual(changes.deleted, [waiting.count - 1])
        XCTAssertEqual(changes.inserted, [landed.count - 2, landed.count - 1])
        XCTAssertEqual(changes.reloaded, [], "插进 Thinking 的同时不能有在原位重画的格子")
    }

    /// 125：真有要重画的格子、上面又插进了一行（断线那一下 Thinking 和「等待接回」一起到）：
    /// 记下它更新后的下标——重画单独一批、在删插之后，用的是新下标。
    func testReloadedRowsAlsoReportTheirIndexAfterInsertsAbove() throws {
        var reply = Message(id: "assistant-ios-1", clientID: "ios-1", sender: .ke, text: "", time: .now,
                            isStreaming: true, deliveryState: .sending)
        let before = ChatTimelineItem.make(messages: [reply], highlightedMessageID: nil, visibleSegmentCount: { _ in nil })
        reply.thoughtSummary = "想一想。"
        reply.deliveryState = .waiting
        let after = ChatTimelineItem.make(messages: [reply], highlightedMessageID: nil, visibleSegmentCount: { _ in nil })

        let changes = try XCTUnwrap(ChatTimelineChanges.between(before, after))
        XCTAssertEqual(changes.inserted, [after.count - 2], "Thinking 插在占位上面")
        XCTAssertEqual(changes.reloaded, [before.count - 1])
        XCTAssertEqual(changes.reloadedAfter, [after.count - 1], "被挤下去一格，重画用新下标")
    }

    func testDoneEventCarriesServerSegments() throws {
        let events = try APIClient.parseStreamPayload(
            #"{"done":true,"assistant_message_id":7,"status":"done","segments":["先过来。","再慢慢说。"]}"#
        )
        guard case let .completed(id, _, status, _, _, _, segments) = events.last else {
            return XCTFail("应该解析出完成事件")
        }
        XCTAssertEqual(id, 7)
        XCTAssertEqual(status, "done")
        XCTAssertEqual(segments, ["先过来。", "再慢慢说。"])

        let old = try APIClient.parseStreamPayload(#"{"done":true,"assistant_message_id":8,"status":"done"}"#)
        guard case let .completed(_, _, _, _, _, _, none) = old.last else { return XCTFail("应该解析出完成事件") }
        XCTAssertNil(none)
    }

    @MainActor
    func testLandedReplyPrefersServerSegments() {
        let landed = ChatViewModel.landedReply(text: "先过来。\n\n再慢慢说。", segments: ["先过来。", "再慢慢说。", " "])
        XCTAssertEqual(landed.text, "先过来。\n\n再慢慢说。")
        XCTAssertEqual(landed.segments, ["先过来。", "再慢慢说。"])
        // 重接时只补了一个 done：用切好的气泡拼回正文
        XCTAssertEqual(ChatViewModel.landedReply(text: "", segments: ["一。", "二。"]).text, "一。\n\n二。")
        // 旧服务器没给切法：原文照收，交给本机切
        let old = ChatViewModel.landedReply(text: "一。\n\n二。", segments: nil)
        XCTAssertEqual(old.text, "一。\n\n二。")
        XCTAssertNil(old.segments)
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
