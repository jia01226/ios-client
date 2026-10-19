import XCTest
@testable import KeApp

@MainActor
private final class ReplyServer: ChatReplyTransport {
    var streams: [AsyncThrowingStream<ChatStreamEvent, Error>.Continuation] = []
    var clientIDs: [String] = []
    var sentTexts: [String] = []
    var sentAttachments: [[ChatAttachment]] = []
    var jobsByID: [String: ActiveChatJob] = [:]
    var history: [Message] = []
    var jobs: [ActiveChatJob] = []
    var completed = false
    var jobReads = 0
    var activeReads = 0
    var cancelledStreams = 0
    var holdNextJob = false
    var heldJob: CheckedContinuation<ActiveChatJob, Error>?
    var reattachCompleted = false

    func activeSession() async throws -> ActiveChatSession { ActiveChatSession(id: 1, model: nil) }
    func activeJobs(sessionID: Int, includeRecentFailures: Bool) async throws -> [ActiveChatJob] {
        activeReads += 1
        return jobs
    }
    func streamMessage(text: String, sessionID: Int, clientMessageID: String, model: String?, attachments: [ChatAttachment]) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        clientIDs.append(clientMessageID)
        sentTexts.append(text)
        sentAttachments.append(attachments)
        return AsyncThrowingStream { continuation in
            streams.append(continuation)
            continuation.onTermination = { [weak self] termination in
                if case .cancelled = termination { Task { @MainActor in self?.cancelledStreams += 1 } }
            }
            if reattachCompleted && streams.count == 2 {
                continuation.yield(.receipt(userMessageID: 100, jobID: "job-1", bedroom: nil))
                continuation.yield(.text("完整回复"))
                continuation.yield(.completed(assistantMessageID: 101, bedroom: nil, status: "done", error: nil, retryable: false, retryScheduled: false))
                continuation.finish()
            }
        }
    }
    func chatJob(id: String, sessionID: Int) async throws -> ActiveChatJob {
        jobReads += 1
        if holdNextJob {
            holdNextJob = false
            return try await withCheckedThrowingContinuation { heldJob = $0 }
        }
        return jobsByID[id] ?? job(id: id, status: completed ? "done" : "running")
    }
    func job(id: String = "job-1", status: String) -> ActiveChatJob {
        ActiveChatJob(id: id, status: status, clientMessageID: clientIDs.first,
                      userMessageID: 100, assistantMessageID: status == "done" ? 101 : nil,
                      error: status == "error" ? "旧连接错误" : nil, retryable: status == "error", nextRetryAt: nil)
    }
    func fetchMessages(sessionID: Int, limit: Int, beforeID: Int?, aroundID: Int?) async throws -> [Message] { history }
    func markSeen(sessionID: Int, throughID: Int?) async throws {}
    func receive(_ events: [ChatStreamEvent], at index: Int = 0) {
        for event in events { streams[index].yield(event) }
    }
    func completeOnServer(segments: [String]? = nil) {
        completed = true
        jobs = [] // Completed replies are intentionally absent from the active list.
        history = [Message(id: "server-100", serverID: 100, sender: .me, text: "测试一句", time: .now),
                   Message(id: "server-101", serverID: 101, sender: .ke,
                           text: segments?.joined(separator: "\n\n") ?? "完整回复", time: .now, segments: segments)]
    }
}

@MainActor
final class ChatForegroundRecoveryTests: XCTestCase {
    func testExternalHandoffWaitsForSessionSendsOnceAndPreservesAttachments() async {
        let server = ReplyServer()
        let vm = ChatViewModel(monitorConnectivity: false, replyTransport: server,
                               cacheFileName: "handoff-\(UUID()).json", replyCompleted: {})
        let id = UUID(), text = "问的是：未来。 [塔罗#7]"
        let early = await vm.sendExternalMessage(id: id, text: text)
        XCTAssertFalse(early); XCTAssertTrue(server.sentTexts.isEmpty)
        await vm.prepareExternalSend()
        XCTAssertTrue(vm.canAcceptExternalMessage)
        let attachment = ChatAttachment(url: "/uploads/draft.png", name: "草稿", kind: "image")
        vm.pendingAttachments = [attachment]
        vm.isRefreshingClaude = true
        let refreshing = await vm.sendExternalMessage(id: id, text: text)
        XCTAssertFalse(refreshing)
        vm.isRefreshingClaude = false; vm.isClearingWindow = true
        let clearing = await vm.sendExternalMessage(id: id, text: text)
        XCTAssertFalse(clearing); vm.isClearingWindow = false
        let sending = Task { await vm.sendExternalMessage(id: id, text: text, reduceMotion: true) }
        await wait { server.streams.count == 1 }
        let duplicate = await vm.sendExternalMessage(id: id, text: text)
        XCTAssertTrue(duplicate); XCTAssertEqual(server.sentTexts, [text])
        XCTAssertTrue(server.sentAttachments[0].isEmpty)
        XCTAssertEqual(vm.pendingAttachments.map(\.url), [attachment.url])
        server.receive([.receipt(userMessageID: 93001, jobID: nil, bedroom: nil), .text("月亮逆位"),
                        .completed(assistantMessageID: 93002, bedroom: nil, status: "done", error: nil, retryable: false, retryScheduled: false)])
        server.streams[0].finish()
        let accepted = await sending.value
        XCTAssertTrue(accepted)
        XCTAssertEqual(vm.messages.first(where: { $0.sender == .me })?.serverID, 93001)
        XCTAssertEqual(vm.messages.first(where: { $0.sender == .me })?.deliveryState, .sent)
        XCTAssertEqual(vm.messages.first(where: { $0.sender == .ke })?.text, "月亮逆位")
    }

    func testExternalHandoffCanSendWhileKeIsReplying() async {
        let server = ReplyServer(); let vm = await model(server)
        let first = await start(vm, server)
        let next = Task { await vm.sendExternalMessage(id: UUID(), text: "十张 [塔罗#8]") }
        await wait { server.streams.count == 2 }
        server.receive([.receipt(userMessageID: 93003, jobID: nil, bedroom: nil)], at: 1)
        let accepted = await next.value
        XCTAssertTrue(accepted)
        XCTAssertEqual(server.sentTexts, ["测试一句", "十张 [塔罗#8]"])
        XCTAssertEqual(vm.messages.first(where: { $0.serverID == 93003 })?.deliveryState, .sent)
        server.receive([.completed(assistantMessageID: 101, bedroom: nil, status: "done", error: nil, retryable: false, retryScheduled: false)])
        server.streams[0].finish(); await first.value
    }

    private func model(_ server: ReplyServer) async -> ChatViewModel {
        let vm = ChatViewModel(monitorConnectivity: false, replyTransport: server,
                               cacheFileName: "recovery-test-\(UUID()).json", replyCompleted: {})
        await vm.bootstrap()
        return vm
    }
    private func wait(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<150 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition did not become true within 1.5s", file: file, line: line)
    }
    private func start(_ vm: ChatViewModel, _ server: ReplyServer, receipt: Bool = true,
                       reduceMotion: Bool = true) async -> Task<Void, Never> {
        let task = Task { await vm.send("测试一句", reduceMotion: reduceMotion) }
        await wait { server.streams.count == 1 }
        if receipt {
            server.receive([.receipt(userMessageID: 100, jobID: "job-1", bedroom: nil), .text("半截")])
            await wait { vm.messages.contains { $0.sender == .me && $0.serverID == 100 } }
            await settle()
            assertNoPartialReply(vm)
        }
        return task
    }
    /// 让已经排在流里的事件都处理完
    private func settle() async { try? await Task.sleep(nanoseconds: 30_000_000) }
    /// 121：柯写的过程中，半截正文不进气泡；那一行只剩时间和「发送中」
    private func assertNoPartialReply(_ vm: ChatViewModel, file: StaticString = #filePath, line: UInt = #line) {
        let pending = vm.messages.filter { $0.sender == .ke && $0.isStreaming }
        XCTAssertFalse(pending.isEmpty, "应该还有一个在写的占位", file: file, line: line)
        for message in pending {
            XCTAssertEqual(message.text, "", file: file, line: line)
            XCTAssertEqual(message.bubbleSegments, [], file: file, line: line)
        }
        XCTAssertTrue(vm.isSending, "顶上一直是「正在输入中」", file: file, line: line)
    }
    private func assertComplete(_ vm: ChatViewModel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(vm.messages.filter { $0.sender == .ke }.map(\.text), ["完整回复"], file: file, line: line)
        XCTAssertEqual(vm.messages.filter { $0.sender == .me }.count, 1, file: file, line: line)
        XCTAssertFalse(vm.messages.contains { $0.isStreaming || $0.deliveryState != .sent }, file: file, line: line)
        XCTAssertNil(vm.replyFailure, file: file, line: line)
        XCTAssertNil(vm.statusText, file: file, line: line)
        XCTAssertFalse(vm.isSending, file: file, line: line)
    }

    func testBackgroundResumeFetchesCompletedKnownJobWithoutWaitingForFrozenStream() async {
        let server = ReplyServer(); let vm = await model(server)
        let sending = await start(vm, server)
        vm.becameInactive(); vm.enteredBackgroundScene()
        server.completeOnServer()
        let began = Date()
        await vm.resumeFromForeground()
        XCTAssertLessThan(Date().timeIntervalSince(began), 2)
        assertComplete(vm)
        XCTAssertEqual(server.jobReads, 1)
        await sending.value
        await wait { server.cancelledStreams == 1 }
        server.streams[0].finish(throwing: URLError(.timedOut))
        assertComplete(vm)
    }

    func testShortInactivityAndOrdinaryForegroundKeepHealthySSE() async {
        let server = ReplyServer(); let vm = await model(server)
        let sending = await start(vm, server)
        let began = Date()
        vm.becameInactive(at: began)
        await vm.resumeFromForeground(at: began.addingTimeInterval(0.5))
        await vm.resumeFromForeground()
        XCTAssertEqual(server.jobReads, 0)
        XCTAssertEqual(server.cancelledStreams, 0)
        XCTAssertTrue(vm.isSending)
        server.completeOnServer()
        server.receive([.text("后半截"), .completed(assistantMessageID: 101, bedroom: nil, status: "done", error: nil, retryable: false, retryScheduled: false)])
        server.streams[0].finish()
        await sending.value
        assertComplete(vm)
    }

    func testLongInactivityAlsoReplacesSuspendedOwner() async {
        let server = ReplyServer(); let vm = await model(server)
        let sending = await start(vm, server)
        let began = Date(); vm.becameInactive(at: began)
        server.completeOnServer()
        await vm.resumeFromForeground(at: began.addingTimeInterval(2.1))
        await sending.value
        assertComplete(vm)
    }

    func testNotificationOpenAndActiveCoalesceWithoutTwoPollers() async {
        let server = ReplyServer(); let vm = await model(server)
        let sending = await start(vm, server)
        server.completeOnServer(); server.holdNextJob = true
        vm.enteredBackgroundScene()
        let resumed = Task { await vm.resumeFromForeground(forceReconnect: true) }
        await wait { server.heldJob != nil }
        await vm.resumeFromForeground() // notification and scene activation can arrive together
        XCTAssertEqual(server.jobReads, 1)
        server.heldJob?.resume(returning: server.job(status: "done")); server.heldJob = nil
        await resumed.value; await sending.value
        assertComplete(vm)
    }

    /// 119：先回前台、再到点推送的 openRequest（forceReconnect），不能把刚起的接回打断重来。
    func testActiveThenNotificationOpenKeepsTheFreshRecovery() async {
        let server = ReplyServer(); let vm = await model(server)
        let sending = await start(vm, server)
        server.completeOnServer(); server.holdNextJob = true
        vm.enteredBackgroundScene()
        let resumed = Task { await vm.resumeFromForeground() }
        await wait { server.heldJob != nil }
        await vm.resumeFromForeground(forceReconnect: true)
        XCTAssertEqual(server.jobReads, 1)
        server.heldJob?.resume(returning: server.job(status: "done")); server.heldJob = nil
        await resumed.value; await sending.value
        assertComplete(vm)
    }

    func testAbandonedPollCannotReportUnauthorizedOrClearNewStream() async {
        let server = ReplyServer(); let vm = await model(server)
        server.holdNextJob = true
        let sending = await start(vm, server)
        server.streams[0].finish(throwing: URLError(.timedOut))
        await wait { server.heldJob != nil }
        vm.enteredBackgroundScene(); server.completeOnServer()
        await vm.resumeFromForeground()
        assertComplete(vm)
        let next = Task { await vm.send("下一句", reduceMotion: true) }
        await wait { server.streams.count == 2 }
        server.heldJob?.resume(throwing: APIError.unauthorized); server.heldJob = nil
        await sending.value
        XCTAssertEqual(vm.phase, .ready)
        XCTAssertTrue(vm.isSending)
        XCTAssertNil(vm.replyFailure)
        server.receive([.receipt(userMessageID: 102, jobID: "job-2", bedroom: nil), .text("新的回复")], at: 1)
        await wait { vm.messages.contains { $0.sender == .me && $0.serverID == 102 } }
        await settle()
        XCTAssertFalse(vm.messages.contains { $0.text == "新的回复" }, "写完之前不露半截")
        server.history += [Message(id: "server-102", serverID: 102, sender: .me, text: "下一句", time: .now), Message(id: "server-103", serverID: 103, sender: .ke, text: "新的回复", time: .now)]
        server.receive([.completed(assistantMessageID: 103, bedroom: nil, status: "done", error: nil, retryable: false, retryScheduled: false)], at: 1)
        server.streams[1].finish(); await next.value
        XCTAssertEqual(vm.messages.filter { $0.sender == .ke }.map(\.text), ["完整回复", "新的回复"])
        XCTAssertFalse(vm.isSending)
    }

    func testResumeBeforeReceiptReusesSameIdempotencyKeyAndPayload() async {
        let server = ReplyServer(); let vm = await model(server)
        let sending = await start(vm, server, receipt: false)
        server.completeOnServer(); server.reattachCompleted = true
        vm.enteredBackgroundScene()
        await vm.resumeFromForeground(); await sending.value
        XCTAssertEqual(server.clientIDs.count, 2)
        XCTAssertEqual(Set(server.clientIDs).count, 1)
        XCTAssertEqual(server.sentTexts, ["测试一句", "测试一句"])
        assertComplete(vm)
    }

    func testFollowUpWithLostReceiptIsRecoveredWithoutDuplicateOrFalseFailure() async {
        let server = ReplyServer(); let vm = await model(server)
        let sending = await start(vm, server)
        let followUp = Task { await vm.send("补充一句", reduceMotion: true) }
        await wait { server.streams.count == 2 }
        let followUpID = server.clientIDs[1]
        server.completeOnServer()
        server.history += [Message(id: "server-102", serverID: 102, sender: .me, text: "补充一句", time: .now),
                           Message(id: "server-103", serverID: 103, sender: .ke, text: "补充的回复", time: .now)]
        server.jobsByID["job-2"] = ActiveChatJob(id: "job-2", status: "done", clientMessageID: followUpID,
            userMessageID: 102, assistantMessageID: 103, error: nil, retryable: false, nextRetryAt: nil)
        vm.enteredBackgroundScene()
        let resumed = Task { await vm.resumeFromForeground() }
        await wait { server.streams.count == 3 }
        XCTAssertEqual(server.clientIDs[2], followUpID)
        XCTAssertEqual(server.sentTexts[2], "补充一句")
        server.streams[1].finish(throwing: URLError(.timedOut))
        server.receive([.receipt(userMessageID: 102, jobID: "job-2", bedroom: nil)], at: 2)
        await resumed.value; await sending.value; await followUp.value
        XCTAssertEqual(vm.messages.filter { $0.sender == .me }.map(\.text), ["测试一句", "补充一句"])
        XCTAssertEqual(vm.messages.filter { $0.sender == .ke }.map(\.text), ["完整回复", "补充的回复"])
        XCTAssertFalse(vm.messages.contains { $0.isStreaming || $0.deliveryState != .sent })
        XCTAssertFalse(vm.isSending)
        XCTAssertNil(vm.replyFailure)
    }

    func testColdStartFetchesReplyAlreadyCompletedWithoutAnActiveJob() async {
        let server = ReplyServer(); server.completeOnServer()
        let vm = await model(server)
        assertComplete(vm)
        XCTAssertEqual(server.jobReads, 0)
        XCTAssertTrue(server.streams.isEmpty)
    }

    func testExplicitRefreshAlsoReplacesAnAlreadyStalledPoll() async {
        let server = ReplyServer(); let vm = await model(server)
        server.holdNextJob = true
        let sending = await start(vm, server)
        server.streams[0].finish(throwing: URLError(.timedOut))
        await wait { server.heldJob != nil }
        server.completeOnServer()
        await vm.retryHistory()
        assertComplete(vm)
        server.heldJob?.resume(throwing: URLError(.timedOut)); server.heldJob = nil
        await sending.value
        assertComplete(vm)
    }

    /// 121：写的时候一个字不露；写完整条放上去，气泡照服务器切好的分、一个个冒出来；
    /// 紧跟着拉回来的记录（同一份切法）不让已经冒出来的气泡重来。
    func testReplyLandsWholeWithServerSegmentsAndHistoryDoesNotRestartReveal() async {
        let server = ReplyServer(); let vm = await model(server)
        let sending = await start(vm, server, reduceMotion: false)
        server.receive([.text("先过来。\n\n让我抱一下。")])
        await settle()
        assertNoPartialReply(vm)

        // 服务器切成三个（前两段在一个气泡里），和本机按空行切出的四个不一样——证明照服务器的
        let segments = ["半截先过来。\n\n让我抱一下。", "嗯。", "再慢慢说。"]
        server.completeOnServer(segments: segments)
        server.receive([.text("\n\n嗯。\n\n再慢慢说。"),
                        .completed(assistantMessageID: 101, bedroom: nil, status: "done", error: nil,
                                   retryable: false, retryScheduled: false, segments: segments)])
        await wait { vm.messages.contains { $0.sender == .ke && !$0.isStreaming } }

        // 还没拉记录：本机那条已经整条放上去，照 done 带来的切法，第一个气泡先出来
        guard let landed = vm.messages.first(where: { $0.sender == .ke }) else { return XCTFail("没有柯的那条") }
        XCTAssertEqual(landed.serverID, 101)
        XCTAssertEqual(landed.text, "半截先过来。\n\n让我抱一下。\n\n嗯。\n\n再慢慢说。")
        XCTAssertEqual(landed.bubbleSegments, segments)
        XCTAssertEqual(vm.visibleSegmentCount(for: landed), 1)

        server.streams[0].finish()
        await sending.value
        let replaced = vm.messages.first { $0.sender == .ke }
        XCTAssertEqual(replaced?.id, landed.id, "沿用本机 id，时间线认得是同一条")
        XCTAssertEqual(replaced?.bubbleSegments, segments)
        XCTAssertFalse(vm.isSending)
        await wait { vm.visibleSegmentCount(for: landed).map { $0 >= 2 } == true }
        let before = vm.visibleSegmentCount(for: landed) ?? 0

        // 又拉一次记录（回前台、点推送都会这样）：切法一样，已经冒出来的不重来
        await vm.retryHistory()
        if let after = vm.messages.first(where: { $0.serverID == 101 }) {
            XCTAssertGreaterThanOrEqual(vm.visibleSegmentCount(for: after) ?? Int.max, before)
        }
        await wait { vm.visibleSegmentCount(for: landed) == nil }
    }

    /// 121：回前台接回的那句也是整条换上、一个个冒出来，中间不露半截。
    func testRecoveredReplyReplacesWaitingPlaceholderAndRevealsServerSegments() async {
        let server = ReplyServer(); let vm = await model(server)
        let sending = await start(vm, server, reduceMotion: false)
        vm.becameInactive(); vm.enteredBackgroundScene()
        let segments = ["回来啦。", "我一直在。"]
        server.completeOnServer(segments: segments)
        await vm.resumeFromForeground()
        let reply = vm.messages.first { $0.sender == .ke }
        XCTAssertEqual(reply?.serverID, 101)
        XCTAssertEqual(reply?.bubbleSegments, segments)
        XCTAssertFalse(reply?.isStreaming ?? true)
        XCTAssertEqual(vm.messages.filter { $0.sender == .ke }.count, 1, "占位在原位换成完整那条，不多出一条")
        if let reply { XCTAssertEqual(vm.visibleSegmentCount(for: reply), 1, "接回来的也一个个冒") }
        await sending.value
        await wait { server.cancelledStreams == 1 }
        server.streams[0].finish(throwing: URLError(.timedOut))
        XCTAssertEqual(vm.messages.first { $0.sender == .ke }?.bubbleSegments, segments)
    }

    /// 121：重接时服务器只补了一个 done、一个字没给：不放一条空气泡上去，等记录拉回来在原位整条换上。
    func testDoneWithoutAnyTextWaitsForHistoryInsteadOfLandingAnEmptyBubble() async {
        let server = ReplyServer(); let vm = await model(server)
        let sending = Task { await vm.send("测试一句", reduceMotion: false) }
        await wait { server.streams.count == 1 }
        let segments = ["接上了。", "刚才断了一下。"]
        server.completeOnServer(segments: segments)
        server.receive([.receipt(userMessageID: 100, jobID: "job-1", bedroom: nil),
                        .completed(assistantMessageID: 101, bedroom: nil, status: "done", error: nil,
                                   retryable: false, retryScheduled: false)])
        await wait { vm.messages.contains { $0.sender == .ke && $0.serverID == 101 } }
        let waiting = vm.messages.first { $0.sender == .ke }
        XCTAssertEqual(waiting?.isStreaming, true)
        XCTAssertEqual(waiting?.bubbleSegments, [])

        server.streams[0].finish()
        await sending.value
        XCTAssertEqual(vm.messages.filter { $0.sender == .ke }.count, 1)
        let reply = vm.messages.first { $0.sender == .ke }
        XCTAssertEqual(reply?.id, waiting?.id)
        XCTAssertEqual(reply?.bubbleSegments, segments)
        if let reply { XCTAssertEqual(vm.visibleSegmentCount(for: reply), 1) }
        XCTAssertFalse(vm.isSending)
    }

    /// 121：连接中途断了：一直是等待的样子，不露半截；接回失败时照旧出失败提示，空位收起。
    func testStreamErrorKeepsWaitingStateWithoutPartialTextUntilFinalFailure() async {
        let server = ReplyServer(); let vm = await model(server)
        server.holdNextJob = true
        let sending = await start(vm, server)
        server.streams[0].finish(throwing: URLError(.networkConnectionLost))
        await wait { server.heldJob != nil }
        let waiting = vm.messages.first { $0.sender == .ke }
        XCTAssertEqual(waiting?.deliveryState, .waiting, "那一行写着「等待接回」")
        XCTAssertEqual(waiting?.text, "")
        XCTAssertEqual(waiting?.bubbleSegments, [])
        XCTAssertTrue(vm.isSending)
        server.heldJob?.resume(returning: server.job(status: "error")); server.heldJob = nil
        await sending.value
        XCTAssertFalse(vm.messages.contains { $0.text == "半截" })
        XCTAssertFalse(vm.messages.contains { $0.sender == .ke }, "没写成的空位收起")
        XCTAssertNotNil(vm.replyFailure)
        XCTAssertFalse(vm.isSending)
    }

    func testNotificationIntentPersistsAndCanRepeat() {
        let coordinator = ChatNotificationCoordinator()
        XCTAssertNil(coordinator.openRequest)
        coordinator.openChat(); let first = coordinator.openRequest
        XCTAssertNotNil(first)
        coordinator.openChat()
        XCTAssertNotEqual(coordinator.openRequest, first)
    }
}
