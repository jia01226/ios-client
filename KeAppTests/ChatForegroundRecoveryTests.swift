import XCTest
@testable import KeApp

@MainActor
private final class ReplyServer: ChatReplyTransport {
    var streams: [AsyncThrowingStream<ChatStreamEvent, Error>.Continuation] = []
    var clientIDs: [String] = []
    var sentTexts: [String] = []
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
    func completeOnServer() {
        completed = true
        jobs = [] // Completed replies are intentionally absent from the active list.
        history = [Message(id: "server-100", serverID: 100, sender: .me, text: "测试一句", time: .now),
                   Message(id: "server-101", serverID: 101, sender: .ke, text: "完整回复", time: .now)]
    }
}

@MainActor
final class ChatForegroundRecoveryTests: XCTestCase {
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
    private func start(_ vm: ChatViewModel, _ server: ReplyServer, receipt: Bool = true) async -> Task<Void, Never> {
        let task = Task { await vm.send("测试一句", reduceMotion: true) }
        await wait { server.streams.count == 1 }
        if receipt {
            server.receive([.receipt(userMessageID: 100, jobID: "job-1", bedroom: nil), .text("半截")])
            await wait { vm.messages.contains { $0.text == "半截" } }
        }
        return task
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
        await wait { vm.messages.contains { $0.text == "新的回复" } }
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

    func testNotificationIntentPersistsAndCanRepeat() {
        let coordinator = ChatNotificationCoordinator()
        XCTAssertNil(coordinator.openRequest)
        coordinator.openChat(); let first = coordinator.openRequest
        XCTAssertNotNil(first)
        coordinator.openChat()
        XCTAssertNotEqual(coordinator.openRequest, first)
    }
}
