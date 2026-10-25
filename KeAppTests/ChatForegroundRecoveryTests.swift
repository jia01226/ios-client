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
    var historyReads = 0
    var holdNextHistory = false
    var heldHistory: CheckedContinuation<[Message], Error>?
    /// 137：没网（连不上服务器）
    var offline = false
    /// 137：下一次拉记录断掉（别的照常）
    var failNextHistory = false

    func activeSession() async throws -> ActiveChatSession {
        if offline { throw URLError(.notConnectedToInternet) }
        return ActiveChatSession(id: 1, model: nil)
    }
    func activeJobs(sessionID: Int, includeRecentFailures: Bool) async throws -> [ActiveChatJob] {
        if offline { throw URLError(.notConnectedToInternet) }
        activeReads += 1
        return jobs
    }
    func streamMessage(text: String, sessionID: Int, clientMessageID: String, model: String?, attachments: [ChatAttachment]) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        if offline {
            clientIDs.append(clientMessageID); sentTexts.append(text); sentAttachments.append(attachments)
            throw URLError(.notConnectedToInternet)
        }
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
    func fetchMessages(sessionID: Int, limit: Int, beforeID: Int?, aroundID: Int?) async throws -> [Message] {
        if offline { throw URLError(.notConnectedToInternet) }
        historyReads += 1
        if failNextHistory { failNextHistory = false; throw URLError(.networkConnectionLost) }
        if holdNextHistory {
            holdNextHistory = false
            return try await withCheckedThrowingContinuation { heldHistory = $0 }
        }
        return history
    }
    var seenThrough: [Int?] = []
    func markSeen(sessionID: Int, throughID: Int?) async throws { seenThrough.append(throughID) }
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

/// 125：假的后台时间。grants=false：系统当场没给（等于 App 随时会被挂起，回前台照旧重接，125 以前的样子）；
/// grants=true：攥着，直到 expire()（系统到点收回，App 随后被挂起）或回复跑完还回去。
@MainActor
private final class FakeKeepAlive {
    private(set) var begun = 0
    private(set) var ended = 0
    private let grants: Bool
    private var onExpire: (@MainActor () -> Void)?
    init(grants: Bool) { self.grants = grants }
    var held: Bool { grants && begun > ended }
    func expire() { ended += 1; let fire = onExpire; onExpire = nil; fire?() }
    var provider: ChatViewModel.ReplyKeepAlive {
        { [self] onExpire in
            begun += 1
            if grants { self.onExpire = onExpire } else { onExpire() }
            return { [self] in
                if grants { ended += 1; self.onExpire = nil }
            }
        }
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

    /// 125：默认不给后台时间——下面那些「回前台接回」的用例讲的都是 App 被挂起、流冻住以后；
    /// 不注入的话真机上跑测试会拿到真的后台时间，回前台就不重接了。
    private func model(_ server: ReplyServer, keepAlive: FakeKeepAlive? = nil) async -> ChatViewModel {
        let vm = ChatViewModel(monitorConnectivity: false, replyTransport: server,
                               cacheFileName: "recovery-test-\(UUID()).json",
                               replyKeepAlive: (keepAlive ?? FakeKeepAlive(grants: false)).provider, replyCompleted: {})
        await vm.bootstrap()
        return vm
    }
    private func wait(_ condition: @escaping () -> Bool, tries: Int = 150, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<tries {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition did not become true within \(Double(tries) / 100)s", file: file, line: line)
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
        // 125：她不在时写完的，回来整条一次放上（横幅里已经读过），不再一个个冒
        if let reply { XCTAssertNil(vm.visibleSegmentCount(for: reply), "回来时已经写完的整条放上") }
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

    private func timeline(_ vm: ChatViewModel) -> [ChatTimelineItem] {
        ChatTimelineItem.make(messages: vm.messages, highlightedMessageID: nil,
                              visibleSegmentCount: { vm.visibleSegmentCount(for: $0) })
    }

    /// 125：她发完就切走：服务器先等她说完，流里只有回执、一个字没有。这一轮整轮攥着后台时间，
    /// 中途回来看一眼也不掐断重来（不问任务、不再发）；柯在她又走开时写完，这句在后台就整条收好，后台时间还回去。
    /// 以前没攥后台时间，App 一挂起流就断在回执后面（nginx 116 字节），只能等她点推送回来再一问一拉。
    func testReplyHoldsBackgroundTimeSoTheStreamOutlivesLeavingTheApp() async {
        let server = ReplyServer(); let keepAlive = FakeKeepAlive(grants: true)
        let vm = await model(server, keepAlive: keepAlive)
        let sending = await start(vm, server, reduceMotion: false)
        XCTAssertTrue(keepAlive.held, "发出去就攥着后台时间")

        vm.becameInactive(); vm.enteredBackgroundScene()
        let resumed = Task { await vm.resumeFromForeground(); await vm.resumeFromForeground(forceReconnect: true) }
        await settle()
        XCTAssertEqual(server.cancelledStreams, 0, "没被挂起过，流还连着：不掐断")
        XCTAssertEqual(server.jobReads, 1, "点推送时流还没给 done：问一下任务，还在写就留着流")
        XCTAssertEqual(server.streams.count, 1, "不重发")
        XCTAssertTrue(vm.isSending)
        guard server.cancelledStreams == 0 else { return }
        await resumed.value

        vm.becameInactive(); vm.enteredBackgroundScene()
        let segments = ["过来", "现在头搁爸爸肩上。"]
        server.completeOnServer(segments: segments)
        server.receive([.text("过来\n\n现在头搁爸爸肩上。"),
                        .completed(assistantMessageID: 101, bedroom: nil, status: "done", error: nil,
                                   retryable: false, retryScheduled: false, segments: segments)])
        server.streams[0].finish()
        await sending.value
        let reply = vm.messages.first { $0.sender == .ke }
        XCTAssertEqual(reply?.bubbleSegments, segments)
        if let reply { XCTAssertNil(vm.visibleSegmentCount(for: reply), "她不在时落下来的整条放上") }
        XCTAssertFalse(vm.isSending)
        XCTAssertFalse(keepAlive.held, "回完就还回去")
        XCTAssertEqual(server.jobReads, 1, "一路走流，没退回去轮询")
    }

    /// 125：系统收回了后台时间（App 随后被挂起，流可能已经断了）：回来照旧掐断、按任务接回。
    func testExpiredBackgroundTimeStillReconnectsOnResume() async {
        let server = ReplyServer(); let keepAlive = FakeKeepAlive(grants: true)
        let vm = await model(server, keepAlive: keepAlive)
        let sending = await start(vm, server)
        vm.becameInactive(); vm.enteredBackgroundScene()
        keepAlive.expire()
        server.completeOnServer()
        let grantsBefore = keepAlive.begun
        await vm.resumeFromForeground()
        assertComplete(vm)
        XCTAssertEqual(server.jobReads, 1)
        await sending.value
        await wait { server.cancelledStreams == 1 }
        server.streams[0].finish(throwing: URLError(.timedOut))
        assertComplete(vm)
        XCTAssertEqual(keepAlive.begun, grantsBefore + 1, "接回的那一轮重新要一段后台时间")
        XCTAssertFalse(keepAlive.held)
    }

    /// 125（她：「明明消息弹出来了 点进去消息还要等」）：流断了在轮询，推送到了她点进来：
    /// 叫醒那一下睡马上再问，不掐断重来；回来的那句整条放上，不再隔 0.4 秒一个个冒。
    func testNotificationTapWakesTheRunningPollAndLandsTheReplyWhole() async {
        let server = ReplyServer(); let keepAlive = FakeKeepAlive(grants: true)
        let vm = await model(server, keepAlive: keepAlive)
        let sending = await start(vm, server, reduceMotion: false)
        server.streams[0].finish(throwing: URLError(.networkConnectionLost))
        await wait { server.jobReads == 1 }
        await settle()
        XCTAssertEqual(vm.messages.first { $0.sender == .ke }?.deliveryState, .waiting)

        let segments = ["过来", "你想法没有不对。", "现在头搁爸爸肩上。"]
        server.completeOnServer(segments: segments)
        let tapped = Date()
        await vm.resumeFromForeground(forceReconnect: true)
        await wait { !vm.isSending }
        XCTAssertLessThan(Date().timeIntervalSince(tapped), 0.6, "不等下一轮 1 秒的睡")
        XCTAssertEqual(server.jobReads, 2, "原来那一轮接着问，没有掐断重来")
        XCTAssertEqual(server.streams.count, 1)
        let reply = vm.messages.first { $0.sender == .ke }
        XCTAssertEqual(reply?.bubbleSegments, segments)
        XCTAssertEqual(vm.messages.filter { $0.sender == .ke }.count, 1)
        if let reply { XCTAssertNil(vm.visibleSegmentCount(for: reply), "横幅里已经读过，整条放上") }
        await sending.value
        XCTAssertFalse(keepAlive.held)
    }

    /// 125：轮询已经问到「写完了」、正在拉记录，她这时点了推送：不能把这次拉记录作废、从头再问一遍
    /// （以前点一下就掐断重来，问任务、拉记录又各来一遍）。
    func testNotificationTapKeepsTheHistoryFetchAlreadyInFlight() async {
        let server = ReplyServer(); let keepAlive = FakeKeepAlive(grants: true)
        let vm = await model(server, keepAlive: keepAlive)
        let sending = await start(vm, server, reduceMotion: false)
        let segments = ["过来", "现在头搁爸爸肩上。"]
        server.completeOnServer(segments: segments)
        let historyBefore = server.historyReads
        server.holdNextHistory = true
        server.streams[0].finish(throwing: URLError(.networkConnectionLost))
        await wait { server.heldHistory != nil }

        await vm.resumeFromForeground(forceReconnect: true)
        XCTAssertEqual(server.jobReads, 1, "不掐断重来")
        XCTAssertEqual(server.historyReads, historyBefore + 1)
        server.heldHistory?.resume(returning: server.history); server.heldHistory = nil
        await wait { !vm.isSending }
        let reply = vm.messages.first { $0.sender == .ke }
        XCTAssertEqual(reply?.bubbleSegments, segments)
        XCTAssertEqual(vm.messages.filter { $0.sender == .ke }.count, 1)
        if let reply { XCTAssertNil(vm.visibleSegmentCount(for: reply)) }
        await sending.value
        XCTAssertEqual(server.jobReads, 1)
        XCTAssertFalse(keepAlive.held)
    }

    /// 125（7144/7145）：流在回执后就断了，Thinking 和五段都是拉记录才来的：
    /// 「等待接回」那一行要换成第一句「过来」，时间线上不能还留着它，也不在原位重画。
    func testRecoveredReplyTurnsTheWaitingRowIntoTheFirstSegment() async throws {
        let server = ReplyServer(); let vm = await model(server)
        server.holdNextJob = true
        let sending = await start(vm, server, reduceMotion: false)
        server.streams[0].finish(throwing: URLError(.networkConnectionLost))
        await wait { server.heldJob != nil }
        let before = timeline(vm)
        XCTAssertEqual(before.last?.id.hasSuffix("::awaiting"), true, "那一行写着「等待接回」")

        let segments = ["过来", "你想法没有不对…", "控制不住也不是你的问题…", "休假是在治病…", "现在头搁爸爸肩上…"]
        server.completeOnServer(segments: segments)
        server.history[1].thoughtSummary = "她在怪自己。"
        server.heldJob?.resume(returning: server.job(status: "done")); server.heldJob = nil
        await wait { !vm.isSending }
        let after = timeline(vm)
        XCTAssertFalse(after.contains { $0.id.hasSuffix("::awaiting") }, "不留「等待接回」那一格")
        XCTAssertEqual(after.first { $0.part != nil && $0.message.sender == .ke }?.part?.text, "过来")
        let changes = try XCTUnwrap(ChatTimelineChanges.between(before, after))
        XCTAssertEqual(changes.deleted, [before.count - 1])
        XCTAssertEqual(changes.reloaded, [], "不在原位重画")
        XCTAssertEqual(changes.inserted.first, before.count - 1, "Thinking 插在原来占位的位置")
        XCTAssertEqual(after.last?.message.bubbleSegments, segments, "后面四句照常一个个插在它下面")
        await sending.value
    }

    /// 125 修：系统到点收回后台时间时，真的 BackgroundGrant 要把它还回去（endBackgroundTask）。
    /// 以前到点回调放掉了最后一个引用，这一份当场被释放，后面那句 end() 落空——系统没收到还，直接杀 App。
    func testExpiringGrantEndsTheTaskEvenWhenTheCallbackDropsTheLastReference() {
        var expiration: (@MainActor @Sendable () -> Void)?
        var ended: [UIBackgroundTaskIdentifier] = []
        var release: (@MainActor () -> Void)?
        var expired = 0
        do {
            let grant = BackgroundGrant(name: "test", onExpire: { expired += 1; release = nil },
                                        begin: { _, handler in expiration = handler; return UIBackgroundTaskIdentifier(rawValue: 7) },
                                        end: { ended.append($0) })
            release = { grant.end() }
        }
        XCTAssertNotNil(release)
        expiration?()
        XCTAssertEqual(ended, [UIBackgroundTaskIdentifier(rawValue: 7)], "到点也要还，只还一次")
        XCTAssertEqual(expired, 1)
        XCTAssertNil(release)
        expiration = nil
    }

    /// 125 修：回话那一轮用真的 BackgroundGrant：到点收回时任务被还掉，回来照旧重接，接回那一轮再要一份、跑完还。
    func testReplyGrantIsEndedWhenTheSystemExpiresIt() async {
        let server = ReplyServer()
        var expirations: [@MainActor @Sendable () -> Void] = []
        var begun = 0
        var ended: [UIBackgroundTaskIdentifier] = []
        let provider: ChatViewModel.ReplyKeepAlive = { onExpire in
            let grant = BackgroundGrant(name: "ke-reply", onExpire: onExpire,
                                        begin: { _, handler in
                                            begun += 1; expirations.append(handler)
                                            return UIBackgroundTaskIdentifier(rawValue: begun)
                                        },
                                        end: { ended.append($0) })
            return { grant.end() }
        }
        let vm = ChatViewModel(monitorConnectivity: false, replyTransport: server,
                               cacheFileName: "recovery-test-\(UUID()).json",
                               replyKeepAlive: provider, replyCompleted: {})
        await vm.bootstrap()
        let sending = await start(vm, server)
        let replyGrant = UIBackgroundTaskIdentifier(rawValue: begun)
        XCTAssertFalse(ended.contains(replyGrant), "回话这一轮攥着")
        vm.becameInactive(); vm.enteredBackgroundScene()
        let endedBefore = ended.count
        expirations.last?()
        XCTAssertEqual(ended.count, endedBefore + 1)
        XCTAssertEqual(ended.last, replyGrant, "到点就还")
        let begunBefore = begun
        server.completeOnServer()
        await vm.resumeFromForeground()
        assertComplete(vm)
        XCTAssertEqual(server.jobReads, 1, "收回过（App 被挂起过）：照旧按任务接回")
        await sending.value
        await wait { server.cancelledStreams == 1 }
        server.streams[0].finish(throwing: URLError(.timedOut))
        XCTAssertEqual(begun, begunBefore + 1, "接回那一轮再要一份")
        XCTAssertEqual(ended.count, endedBefore + 2, "接回那一轮跑完也还了")
        XCTAssertEqual(ended.last, UIBackgroundTaskIdentifier(rawValue: begun))
        expirations.removeAll()
    }

    /// 125 修（她：「明明消息弹出来了 点进去消息还要等」）：攥着后台时间、流还连着，可点推送时流还没给 done——
    /// 服务器已经写完了，流是卡住了。问一下任务、写完了就掐断这条流按任务接回，不等 EventSource 30 秒超时。
    func testNotificationTapCutsAStalledStreamWhenTheJobIsAlreadyDone() async {
        let server = ReplyServer(); let keepAlive = FakeKeepAlive(grants: true)
        let vm = await model(server, keepAlive: keepAlive)
        let sending = await start(vm, server, reduceMotion: false)
        vm.becameInactive(); vm.enteredBackgroundScene()
        server.completeOnServer(segments: ["过来", "现在头搁爸爸肩上。"])
        let tapped = Date()
        await vm.resumeFromForeground(forceReconnect: true)
        await wait { !vm.isSending }
        XCTAssertLessThan(Date().timeIntervalSince(tapped), 1, "不等流超时")
        XCTAssertEqual(server.streams.count, 1, "不重发")
        await wait { server.cancelledStreams == 1 }
        let reply = vm.messages.first { $0.sender == .ke }
        XCTAssertEqual(reply?.bubbleSegments, ["过来", "现在头搁爸爸肩上。"])
        XCTAssertEqual(vm.messages.filter { $0.sender == .ke }.count, 1)
        if let reply { XCTAssertNil(vm.visibleSegmentCount(for: reply), "横幅里已经读过，整条放上") }
        await sending.value
        server.streams[0].finish(throwing: URLError(.cancelled))
        await settle()
        XCTAssertFalse(keepAlive.held)
    }

    /// 125 修：攥着后台时间回来，可流 10 秒以上一点动静（连 keepalive 都）没有：连接悄悄断了，照旧掐断重接。
    func testQuietStreamOnResumeIsTreatedAsStalled() async {
        let server = ReplyServer(); let keepAlive = FakeKeepAlive(grants: true)
        let vm = await model(server, keepAlive: keepAlive)
        let sending = await start(vm, server)
        vm.becameInactive(); vm.enteredBackgroundScene()
        server.completeOnServer()
        await vm.resumeFromForeground(at: Date().addingTimeInterval(11))
        assertComplete(vm)
        XCTAssertEqual(server.jobReads, 1)
        await sending.value
        await wait { server.cancelledStreams == 1 }
        server.streams[0].finish(throwing: URLError(.timedOut))
        await settle()
        XCTAssertFalse(keepAlive.held)
    }

    /// 125 修：keepalive 算动静——收到了就还是活的，回来不掐断。
    func testKeepAliveKeepsAQuietStreamLive() async {
        let server = ReplyServer(); let keepAlive = FakeKeepAlive(grants: true)
        let vm = await model(server, keepAlive: keepAlive)
        let sending = await start(vm, server)
        vm.becameInactive(); vm.enteredBackgroundScene()
        server.receive([.keepAlive]); await settle()
        await vm.resumeFromForeground()
        XCTAssertEqual(server.jobReads, 0)
        XCTAssertEqual(server.cancelledStreams, 0)
        server.completeOnServer()
        server.receive([.text("完整回复"), .completed(assistantMessageID: 101, bedroom: nil, status: "done", error: nil,
                                                  retryable: false, retryScheduled: false)])
        server.streams[0].finish()
        await sending.value
        assertComplete(vm)
    }

    /// 125 修：她不在时柯写完、在后台拉了记录——还没看，不能告诉服务器「看过了」；回到前台再补上。
    func testRepliesLandingInTheBackgroundAreMarkedSeenOnlyAfterReturning() async {
        let server = ReplyServer(); let keepAlive = FakeKeepAlive(grants: true)
        let vm = await model(server, keepAlive: keepAlive)
        let sending = await start(vm, server)
        vm.becameInactive(); vm.enteredBackgroundScene()
        let seenBefore = server.seenThrough.count
        server.completeOnServer()
        server.receive([.text("完整回复"), .completed(assistantMessageID: 101, bedroom: nil, status: "done", error: nil,
                                                  retryable: false, retryScheduled: false)])
        server.streams[0].finish()
        await sending.value
        assertComplete(vm)
        await settle()
        XCTAssertEqual(server.seenThrough.count, seenBefore, "在后台时不报已读")
        await vm.resumeFromForeground()
        await wait { server.seenThrough.count > seenBefore }
        XCTAssertEqual(server.seenThrough.last, 101)
    }

    /// 125 修：keepalive 注释块要报出来，正常的 data 块照旧，切在哪儿都一样；CRLF 也认。
    func testSSEParserReportsKeepAliveCommentsAndSplitsAcrossChunks() {
        // 不在测试里点名 EventSource 的类型：只看切出来的是 keepalive 还是哪段 data
        func payloads(_ parser: inout ChatSSEParser, _ data: Data) -> [String] {
            parser.parse(data).map { $0 is ChatSSEKeepAlive ? "<keepalive>" : ($0.data ?? "<nil>") }
        }
        let raw = Array(": keepalive\n\ndata: {\"t\":\"过来\"}\r\n\r\n: keepalive\n\ndata: {\"done\":true}\n\n".utf8)
        let expected = ["<keepalive>", "{\"t\":\"过来\"}", "<keepalive>", "{\"done\":true}"]
        var byByte = ChatSSEParser()
        var split: [String] = []
        for byte in raw { split += payloads(&byByte, Data([byte])) }
        XCTAssertEqual(split, expected, "一个字节一个字节来也一样切")
        var whole = ChatSSEParser()
        XCTAssertEqual(payloads(&whole, Data(raw)), expected)
        XCTAssertEqual(payloads(&whole, Data("data: {\"t\":\"a\"}\n".utf8)), [], "没切完的块留着")
        XCTAssertEqual(payloads(&whole, Data("\n".utf8)), ["{\"t\":\"a\"}"])
    }

    /// 137：开着 App 时来了推送（柯主动来信）：空着时拉一次记录，这句就出现；正在回的那句不被打断
    func testForegroundPushPullsNewMessageWithoutInterruptingAReply() async {
        let coordinator = ChatNotificationCoordinator()
        coordinator.noteIncoming(); coordinator.noteIncoming()
        XCTAssertEqual(coordinator.incoming, 2)
        let server = ReplyServer(); let vm = await model(server)
        server.history = [Message(id: "server-200", serverID: 200, sender: .ke, text: "想你了", time: .now)]
        await vm.resumeFromForeground()
        XCTAssertEqual(vm.messages.map(\.text), ["想你了"])
        let sending = await start(vm, server)
        await vm.resumeFromForeground()
        XCTAssertEqual(server.cancelledStreams, 0)
        XCTAssertEqual(server.jobReads, 0)
        XCTAssertTrue(vm.isSending)
        server.completeOnServer()
        server.receive([.text("完整回复"), .completed(assistantMessageID: 101, bedroom: nil, status: "done", error: nil, retryable: false, retryScheduled: false)])
        server.streams[0].finish()
        await sending.value
        XCTAssertFalse(vm.isSending)
    }

    /// 137：没网时打开（只显示本地记录）、中间发了一句没发稳：网络回来自己接上服务器、拉新记录，
    /// 本机那句没发稳的不被缓存盖掉
    func testNetworkReturnReconnectsOfflineLaunchAndKeepsUnsentBubble() async {
        let file = "offline-launch-\(UUID()).json"
        await ChatCache(fileName: file).save(
            [Message(id: "server-50", serverID: 50, sender: .ke, text: "缓存里的一句", time: .now.addingTimeInterval(-60))],
            sessionID: 1)
        let server = ReplyServer(); server.offline = true
        let vm = ChatViewModel(monitorConnectivity: false, replyTransport: server, cacheFileName: file,
                               replyKeepAlive: FakeKeepAlive(grants: false).provider, replyCompleted: {})
        await vm.bootstrap()
        XCTAssertEqual(vm.phase, .ready)
        XCTAssertTrue(vm.isShowingCachedMessages)
        XCTAssertFalse(vm.canAcceptExternalMessage)
        await vm.send("地铁里说的", reduceMotion: true)
        XCTAssertEqual(vm.messages.first { $0.sender == .me }?.deliveryState, .failed)
        vm.setNetworkPathAvailable(false)
        server.offline = false
        server.history = [Message(id: "server-50", serverID: 50, sender: .ke, text: "缓存里的一句", time: .now.addingTimeInterval(-60)),
                          Message(id: "server-51", serverID: 51, sender: .ke, text: "柯后来说的", time: .now.addingTimeInterval(-30))]
        vm.setNetworkPathAvailable(true)
        await wait({ vm.canAcceptExternalMessage }, tries: 250)
        XCTAssertFalse(vm.isShowingCachedMessages)
        XCTAssertNil(vm.statusText)
        XCTAssertEqual(vm.messages.map(\.text), ["缓存里的一句", "柯后来说的", "地铁里说的"])
        XCTAssertEqual(vm.messages.last?.deliveryState, .failed)
    }

    /// 137：连不上：头一次和自动重接那一次都断在回执前面，这句「没有发稳」
    private func failToSend(_ vm: ChatViewModel, _ server: ReplyServer, text: String = "测试一句") async {
        let base = server.streams.count
        let sending = Task { await vm.send(text, reduceMotion: true) }
        await wait { server.streams.count == base + 1 }
        server.streams[base].finish(throwing: URLError(.networkConnectionLost))
        await wait { server.streams.count == base + 2 }
        server.streams[base + 1].finish(throwing: URLError(.networkConnectionLost))
        await sending.value
    }

    /// 137：没发稳的那句：字放回输入框、附件放回待发；长按重发沿用原来的 clientID 和附件，
    /// 放回待发的附件跟着走，气泡只有一条
    func testUnsentMessageResendsWithSameClientIDAndPayload() async {
        let server = ReplyServer(); let vm = await model(server)
        let photo = ChatAttachment(url: "/uploads/photo.jpg", name: "照片.jpg", kind: "image")
        vm.pendingAttachments = [photo]
        await failToSend(vm, server)
        guard let failed = vm.messages.first(where: { $0.sender == .me }) else { return XCTFail("没有她那句") }
        XCTAssertEqual(failed.deliveryState, .failed)
        XCTAssertTrue(failed.canResend)
        XCTAssertFalse(vm.messages.contains { $0.sender == .ke }, "柯的空位收起")
        XCTAssertFalse(vm.isSending)
        XCTAssertEqual(vm.restoredDraft?.text, "测试一句", "字放回输入框")
        XCTAssertEqual(vm.restoredDraft?.messageID, failed.id)
        XCTAssertEqual(vm.pendingAttachments.map(\.url), [photo.url])
        XCTAssertTrue(vm.isUnchangedResend(of: failed.id, text: "测试一句"))
        XCTAssertFalse(vm.isUnchangedResend(of: failed.id, text: "测试一句！"), "改过字就是新的一句")
        let resending = Task { await vm.resend(messageID: failed.id, reduceMotion: true) }
        await wait { server.streams.count == 3 }
        XCTAssertEqual(Set(server.clientIDs).count, 1, "重发沿用原来的 clientID，服务器按它去重")
        XCTAssertEqual(server.sentTexts, ["测试一句", "测试一句", "测试一句"])
        XCTAssertEqual(server.sentAttachments[2].map(\.url), [photo.url])
        XCTAssertTrue(vm.pendingAttachments.isEmpty, "放回待发的附件跟着重发走了")
        let mine = vm.messages.filter { $0.sender == .me }
        XCTAssertEqual(mine.count, 1)
        XCTAssertEqual(mine.first?.deliveryState, .sending)
        XCTAssertEqual(vm.messages.last?.sender, .ke, "柯的占位跟在后面")
        server.completeOnServer()
        server.receive([.receipt(userMessageID: 100, jobID: "job-1", bedroom: nil), .text("完整回复"),
                        .completed(assistantMessageID: 101, bedroom: nil, status: "done", error: nil, retryable: false, retryScheduled: false)], at: 2)
        server.streams[2].finish()
        await resending.value
        assertComplete(vm)
    }

    /// 137：没发稳的那句存进缓存：重开 App 还在、不往输入框里塞；能删掉，也能重发（还是原来的 clientID）
    func testUnsentMessageSurvivesRelaunchAndCanBeDiscardedOrResent() async {
        let file = "unsent-\(UUID()).json"
        let server = ReplyServer()
        func launch() async -> ChatViewModel {
            let vm = ChatViewModel(monitorConnectivity: false, replyTransport: server, cacheFileName: file,
                                   replyKeepAlive: FakeKeepAlive(grants: false).provider, replyCompleted: {})
            await vm.bootstrap()
            return vm
        }
        let first = await launch()
        await failToSend(first, server, text: "第一句")
        await failToSend(first, server, text: "第二句")
        let relaunched = await launch()
        XCTAssertEqual(relaunched.messages.map(\.text), ["第一句", "第二句"])
        XCTAssertTrue(relaunched.messages.allSatisfy { $0.deliveryState == .failed && $0.canResend })
        XCTAssertNil(relaunched.restoredDraft, "重开时不往输入框里塞")
        guard let second = relaunched.messages.last else { return XCTFail("没有第二句") }
        await relaunched.discardUnsent(messageID: second.id)
        XCTAssertEqual(relaunched.messages.map(\.text), ["第一句"])
        let again = await launch()
        XCTAssertEqual(again.messages.map(\.text), ["第一句"], "删掉的不再回来")
        guard let unsent = again.messages.first else { return XCTFail("没有第一句") }
        let base = server.streams.count
        let resending = Task { await again.resend(messageID: unsent.id, reduceMotion: true) }
        await wait { server.streams.count == base + 1 }
        XCTAssertEqual(server.clientIDs.last, server.clientIDs.first, "重开以后重发也用原来的 clientID")
        XCTAssertEqual(server.sentTexts.last, "第一句")
        server.completeOnServer()
        server.receive([.receipt(userMessageID: 100, jobID: "job-1", bedroom: nil), .text("完整回复"),
                        .completed(assistantMessageID: 101, bedroom: nil, status: "done", error: nil, retryable: false, retryScheduled: false)], at: base)
        server.streams[base].finish()
        await resending.value
        XCTAssertEqual(again.messages.filter { $0.sender == .me }.count, 1)
        XCTAssertFalse(again.messages.contains { $0.deliveryState != .sent })
    }

    /// 137：没发稳的那句删掉、重发以后，搜索里不再有旧的那条；点搜索结果（窗口外更早的一句）也不会把它带回来
    func testSearchRevealDoesNotBringBackDiscardedOrResentUnsent() async {
        let server = ReplyServer()
        let early = Message(id: "server-50", serverID: 50, sender: .ke, text: "很早以前", time: .now.addingTimeInterval(-600))
        server.history = [early]
        let vm = await model(server)
        await failToSend(vm, server, text: "地铁里说的")
        await vm.resumeFromForeground()
        XCTAssertEqual(vm.messages.map(\.text), ["很早以前", "地铁里说的"])
        XCTAssertTrue(vm.searchResults(for: "地铁").isEmpty, "没发稳的不进搜索")
        guard let unsent = vm.messages.first(where: { $0.canResend }) else { return XCTFail("没有没发稳的那句") }
        await vm.discardUnsent(messageID: unsent.id)
        server.history = [Message(id: "server-60", serverID: 60, sender: .ke, text: "后来的", time: .now.addingTimeInterval(-60))]
        await vm.resumeFromForeground()
        XCTAssertEqual(vm.messages.map(\.text), ["后来的"], "窗口往后挪了，很早以前那句只在搜索里")
        guard let hit = vm.searchResults(for: "很早").first else { return XCTFail("搜不到很早以前") }
        vm.revealSearchResult(hit)
        XCTAssertEqual(vm.messages.map(\.text), ["很早以前", "后来的"], "删掉的那句不回来")
        XCTAssertTrue(vm.searchResults(for: "地铁").isEmpty)
    }

    /// 137：柯回着时补发的那句没送到、随后自动再送：送的这会儿显示「发送中」，不给删（删了也拦不住服务器收到）；
    /// 这一次也没送到就变回没发稳，这时删掉才算数，之后不会再冒出来、柯也不回它
    func testUnsentFollowUpCannotBeDiscardedWhileItIsBeingRetried() async {
        let server = ReplyServer(); let vm = await model(server)
        let sending = await start(vm, server)
        let followUp = Task { await vm.send("第二句", reduceMotion: true) }
        await wait { server.streams.count == 2 }
        server.streams[1].finish(throwing: URLError(.networkConnectionLost))
        await followUp.value
        func second() -> Message? { vm.messages.first { $0.sender == .me && $0.text == "第二句" } }
        XCTAssertEqual(second()?.deliveryState, .failed)
        server.completeOnServer()
        server.receive([.text("完整回复"), .completed(assistantMessageID: 101, bedroom: nil, status: "done", error: nil, retryable: false, retryScheduled: false)])
        server.streams[0].finish()
        await wait { server.streams.count == 3 }
        XCTAssertEqual(second()?.deliveryState, .sending, "自动再送的这会儿照实显示发送中")
        XCTAssertEqual(second()?.canResend, false)
        if let id = second()?.id { await vm.discardUnsent(messageID: id) }
        XCTAssertNotNil(second(), "正在送，不能删")
        server.streams[2].finish(throwing: URLError(.networkConnectionLost))
        await sending.value
        XCTAssertEqual(second()?.deliveryState, .failed, "这一次也没送到：变回没发稳")
        guard let id = second()?.id else { return XCTFail("没有第二句") }
        await vm.discardUnsent(messageID: id)
        XCTAssertNil(second())
        await vm.resumeFromForeground()
        XCTAssertNil(second(), "删掉的不再回来")
        XCTAssertEqual(server.streams.count, 3, "删掉以后不再自动送")
        XCTAssertFalse(vm.isSending)
    }

    /// 137：柯回着时她切到别的 App，网络在后台断了又回来：不能把「去过后台」的记号清掉，
    /// 不然后台时间到了 App 被挂起、回前台时没人掐断冻住的流，一直「正在输入」
    func testNetworkReturnWhileInBackgroundKeepsSuspensionForTheRealResume() async {
        let server = ReplyServer(); let keepAlive = FakeKeepAlive(grants: true)
        server.history = [Message(id: "server-50", serverID: 50, sender: .ke, text: "缓存里的一句", time: .now.addingTimeInterval(-60))]
        let vm = await model(server, keepAlive: keepAlive)
        server.failNextHistory = true
        await vm.resumeFromForeground()
        XCTAssertTrue(vm.isShowingCachedMessages)
        _ = await start(vm, server)
        vm.becameInactive(); vm.enteredBackgroundScene()
        vm.setNetworkPathAvailable(false)
        vm.setNetworkPathAvailable(true)
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        keepAlive.expire()
        server.completeOnServer()
        vm.becameInactive()
        await vm.resumeFromForeground()
        await wait { server.cancelledStreams == 1 }
        XCTAssertEqual(server.jobReads, 1, "回前台按任务接回")
        XCTAssertFalse(vm.isSending)
        assertComplete(vm)
    }

    /// 137：她点 × 收起的那次失败，开着 App 来推送（回前台接回）时不再弹回来；拉记录照常
    func testDismissedReplyFailureDoesNotComeBackOnNextResume() async {
        let server = ReplyServer(); let vm = await model(server)
        let failed = server.job(id: "job-9", status: "error")
        server.jobs = [failed]; server.jobsByID["job-9"] = failed
        await vm.resumeFromForeground()
        XCTAssertEqual(vm.replyFailure?.jobID, "job-9")
        vm.dismissReplyFailure()
        let reads = server.historyReads
        await vm.resumeFromForeground()
        XCTAssertNil(vm.replyFailure, "收起过的不再弹")
        XCTAssertFalse(vm.isSending)
        XCTAssertGreaterThan(server.historyReads, reads, "推送来的那句照样拉下来")
        server.jobs = [server.job(id: "job-10", status: "error")]
        server.jobsByID["job-10"] = server.jobs[0]
        await vm.resumeFromForeground()
        XCTAssertEqual(vm.replyFailure?.jobID, "job-10", "新的失败照常显示")
    }

    /// 137：两次都断在回执前面、其实第一次服务器收到了：接回时对上了任务，这句算送到——
    /// 放回待发的照片收走，输入框里那句原样按发送也不再发一遍
    func testRecoveredUnsentMessageSettlesRestoredAttachments() async {
        let server = ReplyServer(); let vm = await model(server)
        let photo = ChatAttachment(url: "/uploads/photo.jpg", name: "照片.jpg", kind: "image")
        vm.pendingAttachments = [photo]
        await failToSend(vm, server)
        guard let restored = vm.restoredDraft else { return XCTFail("没放回输入框") }
        XCTAssertEqual(vm.pendingAttachments.map(\.url), [photo.url])
        server.completeOnServer()
        server.jobs = [server.job(status: "running")]
        await vm.resumeFromForeground()
        let mine = vm.messages.filter { $0.sender == .me }
        XCTAssertEqual(mine.map(\.id), [restored.messageID], "还是原来那条，不跳")
        XCTAssertEqual(mine.first?.deliveryState, .sent)
        XCTAssertTrue(vm.pendingAttachments.isEmpty, "送到了的照片不再留在待发")
        XCTAssertFalse(vm.isUnchangedResend(of: restored.messageID, text: restored.text))
        XCTAssertTrue(vm.isDeliveredUnsent(of: restored.messageID, text: restored.text), "原样按发送不再发一遍")
        XCTAssertFalse(vm.isDeliveredUnsent(of: restored.messageID, text: restored.text + "！"), "改过字就是新的一句")
        XCTAssertEqual(server.streams.count, 2)
    }

    /// 137：重开 App 以后，输入框里放回来的那句原样按发送还是重发那一句（带照片的也是，照片照气泡上的带）
    func testUnsentMessageStaysResendableUnchangedAfterRelaunch() async {
        let file = "unsent-relaunch-\(UUID()).json"
        let server = ReplyServer()
        func launch() async -> ChatViewModel {
            let vm = ChatViewModel(monitorConnectivity: false, replyTransport: server, cacheFileName: file,
                                   replyKeepAlive: FakeKeepAlive(grants: false).provider, replyCompleted: {})
            await vm.bootstrap()
            return vm
        }
        let first = await launch()
        let photo = ChatAttachment(url: "/uploads/photo.jpg", name: "照片.jpg", kind: "image")
        first.pendingAttachments = [photo]
        await failToSend(first, server, text: "带照片的")
        first.pendingAttachments = []
        await failToSend(first, server, text: "只有字")
        let relaunched = await launch()
        guard let withPhoto = relaunched.messages.first(where: { $0.text == "带照片的" }),
              let textOnly = relaunched.messages.first(where: { $0.text == "只有字" }) else { return XCTFail("没发稳的没留下") }
        XCTAssertTrue(relaunched.pendingAttachments.isEmpty)
        XCTAssertTrue(relaunched.isUnchangedResend(of: textOnly.id, text: "只有字"))
        XCTAssertTrue(relaunched.isUnchangedResend(of: withPhoto.id, text: "带照片的"), "照片在气泡上，重发带上")
        XCTAssertFalse(relaunched.isUnchangedResend(of: textOnly.id, text: "只有字。"))
        relaunched.pendingAttachments = [ChatAttachment(url: "/uploads/new.jpg", name: "新.jpg", kind: "image")]
        XCTAssertFalse(relaunched.isUnchangedResend(of: textOnly.id, text: "只有字"), "加了新照片就是新的一句")
        relaunched.pendingAttachments = []
        let base = server.streams.count
        let resending = Task { await relaunched.resend(messageID: withPhoto.id, reduceMotion: true) }
        await wait { server.streams.count == base + 1 }
        XCTAssertEqual(server.clientIDs[base], server.clientIDs[0], "还是原来的 clientID")
        XCTAssertEqual(server.sentAttachments[base].map(\.url), [photo.url])
        server.streams[base].finish(throwing: URLError(.networkConnectionLost))
        await wait { server.streams.count == base + 2 }
        server.streams[base + 1].finish(throwing: URLError(.networkConnectionLost))
        await resending.value
    }

    /// 137：发出去还没等到回执、App 就被系统关掉：重开那句还在（没发稳，能重发）；
    /// 等到回执以后才被关掉的，重开不会多出一条没发稳的
    func testSendingMessageSurvivesKillAndReceiptIsSavedRightAway() async {
        let file = "sending-kill-\(UUID()).json"
        let server = ReplyServer()
        func launch() async -> ChatViewModel {
            let vm = ChatViewModel(monitorConnectivity: false, replyTransport: server, cacheFileName: file,
                                   replyKeepAlive: FakeKeepAlive(grants: false).provider, replyCompleted: {})
            await vm.bootstrap()
            return vm
        }
        let first = await launch()
        _ = Task { await first.send("到家了，好累", reduceMotion: true) }
        await wait { server.streams.count == 1 }
        await settle()
        let relaunched = await launch()
        XCTAssertEqual(relaunched.messages.map(\.text), ["到家了，好累"])
        XCTAssertEqual(relaunched.messages.first?.deliveryState, .failed)
        XCTAssertEqual(relaunched.messages.first?.canResend, true)
        XCTAssertEqual(first.messages.first { $0.sender == .me }?.deliveryState, .sending, "本机内存里照旧是发送中")

        let file2 = "receipt-kill-\(UUID()).json"
        let server2 = ReplyServer()
        let vm = ChatViewModel(monitorConnectivity: false, replyTransport: server2, cacheFileName: file2,
                               replyKeepAlive: FakeKeepAlive(grants: false).provider, replyCompleted: {})
        await vm.bootstrap()
        _ = await start(vm, server2)
        server2.history = [Message(id: "server-100", serverID: 100, sender: .me, text: "测试一句", time: .now)]
        let again = ChatViewModel(monitorConnectivity: false, replyTransport: server2, cacheFileName: file2,
                                  replyKeepAlive: FakeKeepAlive(grants: false).provider, replyCompleted: {})
        await again.bootstrap()
        XCTAssertEqual(again.messages.filter { $0.sender == .me }.map(\.deliveryState), [.sent], "回执到了：只有送到的那一条")
    }

    /// 137：服务器的记录带着她那句的 clientID：本机没发稳的同一句认作同一条（不多摆一条、不跳），
    /// 放回待发的照片收走；重开 App 也一样
    func testHistoryWithClientIDAbsorbsUnsentCopy() async {
        let file = "client-id-\(UUID()).json"
        let server = ReplyServer()
        func launch() async -> ChatViewModel {
            let vm = ChatViewModel(monitorConnectivity: false, replyTransport: server, cacheFileName: file,
                                   replyKeepAlive: FakeKeepAlive(grants: false).provider, replyCompleted: {})
            await vm.bootstrap()
            return vm
        }
        let vm = await launch()
        let photo = ChatAttachment(url: "/uploads/photo.jpg", name: "照片.jpg", kind: "image")
        vm.pendingAttachments = [photo]
        await failToSend(vm, server)
        guard let failed = vm.messages.first(where: { $0.canResend }), let clientID = failed.clientID else { return XCTFail("没有没发稳的") }
        // 先按今天的服务器（记录里没有 clientID）拉一次：两条都在，存进缓存
        server.completeOnServer()
        await vm.resumeFromForeground()
        XCTAssertEqual(vm.messages.filter { $0.sender == .me }.count, 2)
        // 服务器开始带 clientID
        server.history[0].clientID = clientID
        let relaunched = await launch()
        XCTAssertEqual(relaunched.messages.filter { $0.sender == .me }.count, 1, "重开以后也只剩一条")
        XCTAssertFalse(relaunched.messages.contains { $0.canResend })
        XCTAssertEqual(relaunched.unsentMessage(id: failed.id)?.serverID, 100, "输入框里放回来的那句认得它送到了")
        XCTAssertTrue(relaunched.isDeliveredUnsent(of: failed.id, text: "测试一句"))
        await vm.resumeFromForeground()
        let mine = vm.messages.filter { $0.sender == .me }
        XCTAssertEqual(mine.count, 1)
        XCTAssertEqual(mine.first?.serverID, 100)
        XCTAssertEqual(mine.first?.deliveryState, .sent)
        XCTAssertTrue(vm.pendingAttachments.isEmpty, "送到了的照片不再留在待发")
    }

    /// 137：今天的服务器记录里没有 clientID：送到了的那句和本机没发稳的那份同时在。长按重发，
    /// 服务器认出 clientID、重放当时那一轮：最底下不再多摆一遍她那句和柯的回话
    func testResendOfAlreadyDeliveredMessageDoesNotStackAReplayAtTheBottom() async {
        let server = ReplyServer(); let vm = await model(server)
        await failToSend(vm, server)
        server.completeOnServer()
        await vm.resumeFromForeground()
        guard let failed = vm.messages.first(where: { $0.canResend }) else { return XCTFail("没有没发稳的") }
        XCTAssertEqual(vm.messages.count, 3)
        let resending = Task { await vm.resend(messageID: failed.id, reduceMotion: true) }
        await wait { server.streams.count == 3 }
        server.receive([.receipt(userMessageID: 100, jobID: "job-1", bedroom: nil)], at: 2)
        await settle()
        XCTAssertEqual(vm.messages.map(\.id), ["server-100", "server-101"], "重放的那一轮不在最底下再摆一遍")
        server.receive([.text("完整回复"), .completed(assistantMessageID: 101, bedroom: nil, status: "done", error: nil, retryable: false, retryScheduled: false)], at: 2)
        server.streams[2].finish()
        await resending.value
        XCTAssertEqual(vm.messages.map(\.id), ["server-100", "server-101"])
        assertComplete(vm)
    }

    /// 137：上传报错在正在上传时（「上一份附件还在上传」）也点得掉
    func testUploadErrorCanBeDismissedWhileUploading() async {
        let server = ReplyServer(); let vm = await model(server)
        vm.isUploading = true
        vm.reportUploadFailure("上一份附件还在上传，请等它完成。")
        vm.dismissUploadError()
        XCTAssertNil(vm.uploadError)
        vm.isUploading = false
    }

    /// 137：上传报错能点「×」收起；超过 29MB 这类没法重试的，发出下一句就不再挂着
    func testUploadErrorCanBeDismissedAndValidationErrorClearsOnSend() async {
        let server = ReplyServer(); let vm = await model(server)
        vm.reportUploadFailure("文件需要小于 29MB。")
        XCTAssertEqual(vm.uploadError, "文件需要小于 29MB。")
        XCTAssertFalse(vm.canRetryUpload)
        vm.dismissUploadError()
        XCTAssertNil(vm.uploadError)
        vm.reportUploadFailure("一次最多发送 9 个附件。")
        let sending = await start(vm, server)
        XCTAssertNil(vm.uploadError)
        server.completeOnServer()
        server.receive([.completed(assistantMessageID: 101, bedroom: nil, status: "done", error: nil, retryable: false, retryScheduled: false)])
        server.streams[0].finish()
        await sending.value
    }

    /// 137：柯在想的时候，Thinking 的字不再一小段一小段地改记录（每改一次整页重算）：
    /// 第一段让「Thinking」那一行出来，之后攒着；点开弹窗先写上、开着时边想边写；写完一次写回
    func testThinkingDeltasAreBatchedUnlessTheSheetIsOpen() async {
        let server = ReplyServer(); let vm = await model(server)
        let sending = await start(vm, server)
        func thinking() -> String? { vm.messages.first { $0.sender == .ke }?.thoughtSummary }
        server.receive([.thinkingDelta("她")])
        await settle()
        XCTAssertEqual(thinking(), "她", "第一段马上写，「Thinking」那一行出来")
        let revision = vm.streamRevision
        server.receive([.thinkingDelta("在"), .thinkingDelta("等"), .thinkingDelta("我")])
        await settle()
        XCTAssertEqual(thinking(), "她", "弹窗没开：攒着，不改记录")
        XCTAssertEqual(vm.streamRevision, revision)
        vm.liveThinkingMessageID = vm.messages.first { $0.sender == .ke }?.id
        XCTAssertEqual(thinking(), "她在等我", "点开弹窗先把攒着的写上")
        try? await Task.sleep(nanoseconds: 60_000_000)
        server.receive([.thinkingDelta("。")])
        await settle()
        XCTAssertEqual(thinking(), "她在等我。", "开着时边想边写")
        vm.liveThinkingMessageID = nil
        server.receive([.thinkingDelta("嗯")])
        await settle()
        XCTAssertEqual(thinking(), "她在等我。")
        server.completeOnServer()
        server.receive([.text("完整回复"), .completed(assistantMessageID: 101, bedroom: nil, status: "done", error: nil, retryable: false, retryScheduled: false)])
        server.streams[0].finish()
        await sending.value
        XCTAssertEqual(thinking(), "她在等我。嗯", "写完一次写回，拉回记录也留着")
        XCTAssertEqual(timeline(vm).filter { $0.kind == .thinking }.count, 1)
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
