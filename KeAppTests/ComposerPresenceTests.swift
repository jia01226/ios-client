import XCTest
@testable import KeApp

/// 121：输入框的动静——删光、卡住、切走什么时候报，发出去之后清零。时间用手拨的钟，不真等。
@MainActor final class ComposerPresenceTests: XCTestCase {
    private typealias Event = ComposerPresenceReporter.Event

    func testTypingIsThrottledAndEmptyIsNotRepeated() async {
        let h = PresenceHarness()
        h.type("a")
        h.type("ab")
        h.type("abc")
        await h.advance(1)
        XCTAssertEqual(h.events, [.typing(length: 1)], "1.5 秒里只报头一下")
        await h.advance(0.5)
        XCTAssertEqual(h.events, [.typing(length: 1), .typing(length: 3)], "到点补报最新字数")
        await h.advance(5)
        h.type("")
        h.type("")
        await h.advance(10)
        XCTAssertEqual(h.events.last, .typing(length: 0))
        XCTAssertEqual(h.events.count, 3, "空着又空着不报；不到 4 个字删光也不报")
    }

    func testClearedAfterThreeQuietSecondsThenDraftStartsOver() async {
        let h = PresenceHarness()
        h.type("你好你好呀")
        await h.advance(2)
        h.type("")
        await h.advance(2.9)
        XCTAssertEqual(h.hesitations, [])
        await h.advance(0.1)
        XCTAssertEqual(h.hesitations, [.hesitate(.cleared, peak: 5)])
        await h.advance(120)
        XCTAssertEqual(h.hesitations.count, 1, "空着不会再算卡住")

        h.type("ab")
        h.type("")
        await h.advance(3)
        XCTAssertEqual(h.hesitations.count, 1, "删光之后 peak 从头算，2 个字不报")
    }

    func testRetypingWithinThreeSecondsKeepsTheDraft() async {
        let h = PresenceHarness()
        h.type("abcd")
        h.type("")
        await h.advance(2)
        h.type("x")
        await h.advance(10)
        XCTAssertEqual(h.hesitations, [], "3 秒内又打了字，不算删光")
        h.type("")
        await h.advance(3)
        XCTAssertEqual(h.hesitations, [.hesitate(.cleared, peak: 4)], "peak 还是这份草稿最多的那次")
    }

    func testShortDraftIsIgnored() async {
        let h = PresenceHarness()
        h.type("abc")
        await h.advance(90)
        h.type("")
        await h.advance(3)
        XCTAssertEqual(h.hesitations, [])
    }

    func testStuckOncePerDraftAfterNinetyQuietSeconds() async {
        let h = PresenceHarness()
        h.type("在吗在吗")
        await h.advance(60)
        h.type("在吗在吗？")
        await h.advance(89.9)
        XCTAssertEqual(h.hesitations, [], "改了字就重新数 90 秒")
        await h.advance(0.1)
        XCTAssertEqual(h.hesitations, [.hesitate(.stuck, peak: 5)])
        await h.advance(300)
        h.type("在吗在吗？？")
        await h.advance(300)
        XCTAssertEqual(h.hesitations.count, 1, "同一份草稿只报一次")
    }

    func testSendEndsTheDraftQuietly() async {
        let h = PresenceHarness()
        h.type("abcdef")
        await h.advance(1)
        h.reporter.didSend()
        h.type("")
        await h.advance(200)
        XCTAssertEqual(h.events, [.typing(length: 6)], "发出去之后清空输入框什么都不报")

        h.type("wxyz")
        await h.advance(90)
        XCTAssertEqual(Array(h.events.suffix(2)), [.typing(length: 4), .hesitate(.stuck, peak: 4)], "新的一份重新算")
    }

    func testLeftWhenBackgroundedWithUnsentText() async {
        let h = PresenceHarness()
        h.type("abcd")
        h.reporter.didEnterBackground()
        h.reporter.didEnterBackground()
        XCTAssertEqual(h.hesitations, [.hesitate(.left, peak: 4)])
        await h.advance(200)
        XCTAssertEqual(h.hesitations.count, 1, "在后台不数卡住")
        h.reporter.didBecomeActive()
        await h.advance(90)
        XCTAssertEqual(h.hesitations.last, .hesitate(.stuck, peak: 4), "回来还是不发，重新数 90 秒")
    }

    func testBackgroundRightAfterClearingReportsClearedOnce() async {
        let h = PresenceHarness()
        h.type("abcde")
        h.type("")
        await h.advance(1)
        h.reporter.didEnterBackground()
        XCTAssertEqual(h.hesitations, [.hesitate(.cleared, peak: 5)])
        await h.advance(10)
        XCTAssertEqual(h.hesitations.count, 1)
    }

    /// 137：没发的草稿按线路存在本机；删光（只剩空格换行）就清掉
    func testDraftIsKeptPerLineAndClearedWhenEmpty() throws {
        let suite = "chat-draft-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ChatDraftStore.load(.test1, defaults: defaults), "")
        ChatDraftStore.save("上次没写完的\n那句话", for: .test1, defaults: defaults)
        ChatDraftStore.save("另一条线", for: .main, defaults: defaults)
        XCTAssertEqual(ChatDraftStore.load(.test1, defaults: defaults), "上次没写完的\n那句话")
        XCTAssertEqual(ChatDraftStore.load(.main, defaults: defaults), "另一条线")
        ChatDraftStore.save(" \n ", for: .test1, defaults: defaults)
        XCTAssertEqual(ChatDraftStore.load(.test1, defaults: defaults), "")
        XCTAssertNil(defaults.object(forKey: ChatDraftStore.key(.test1)))
        XCTAssertEqual(ChatDraftStore.load(.main, defaults: defaults), "另一条线")
    }

    func testRestoredDraftDoesNotCount() async {
        let h = PresenceHarness()
        h.reporter.adoptRestoredDraft("上次没写完的那句话")
        h.type("上次没写完的那句话")
        await h.advance(200)
        h.reporter.didEnterBackground()
        h.reporter.didBecomeActive()
        h.type("")
        await h.advance(10)
        XCTAssertEqual(h.events, [], "恢复的草稿不算打字、不算卡住和删光")
    }
}

@MainActor private final class PresenceHarness {
    let clock = PresenceClock()
    private(set) var events: [ComposerPresenceReporter.Event] = []
    private(set) var reporter: ComposerPresenceReporter!

    init() {
        let clock = clock
        reporter = ComposerPresenceReporter(
            now: { clock.now },
            sleep: { try await clock.sleep($0) },
            emit: { [weak self] in self?.events.append($0) }
        )
    }

    var hesitations: [ComposerPresenceReporter.Event] {
        events.filter { if case .hesitate = $0 { return true } else { return false } }
    }

    func type(_ text: String) { reporter.textChanged(text) }
    func advance(_ seconds: TimeInterval) async { await clock.advance(by: seconds) }
}

/// 手拨的钟：sleep 挂起直到 advance 拨过它的点；被取消就抛 CancellationError。
@MainActor private final class PresenceClock {
    private(set) var now = Date(timeIntervalSinceReferenceDate: 0)
    private var sleepers: [(id: Int, deadline: Date, continuation: CheckedContinuation<Void, Error>)] = []
    private var nextID = 0

    func sleep(_ seconds: TimeInterval) async throws {
        nextID += 1
        let id = nextID
        let deadline = now.addingTimeInterval(seconds)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepers.append((id, deadline, continuation))
            }
        } onCancel: {
            Task { @MainActor in self.wake(id, throwing: CancellationError()) }
        }
    }

    func advance(by seconds: TimeInterval) async {
        let target = now.addingTimeInterval(seconds)
        // 2.9 + 0.1 这类小数加起来可能差一丝，留一点余量
        let reach = target.addingTimeInterval(1e-6)
        await settle()
        while let next = sleepers.filter({ $0.deadline <= reach }).min(by: { $0.deadline < $1.deadline }) {
            now = next.deadline
            wake(next.id)
            await settle()
        }
        now = target
        await settle()
    }

    private func wake(_ id: Int, throwing error: Error? = nil) {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
        let sleeper = sleepers.remove(at: index)
        if let error { sleeper.continuation.resume(throwing: error) } else { sleeper.continuation.resume() }
    }

    /// 让刚起的、刚醒的、刚被取消的计时都在主线程上跑一轮
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}
