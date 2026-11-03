import XCTest
@testable import KeApp

private actor FakeWorkshop: WorkshopAPI {
    var snapshot: WorkshopSnapshot
    var events: [WorkshopEvent] = []
    var sent: [String] = []
    var stops = 0

    init(snapshot: WorkshopSnapshot) { self.snapshot = snapshot }

    func setSnapshot(_ s: WorkshopSnapshot) { snapshot = s }
    func setEvents(_ e: [WorkshopEvent]) { events = e }

    func fetchWorkshop() async throws -> WorkshopSnapshot { snapshot }
    func sendWorkshop(text: String, model: String?) async throws -> WorkshopSendResult {
        sent.append(text)
        return WorkshopSendResult(queued: false, message_id: 9, job_id: "job1")
    }
    func workshopEvents(jobID: String, after: Int) async throws -> AsyncThrowingStream<WorkshopEvent, Error> {
        let list = events.filter { $0.seq > after }
        return AsyncThrowingStream { c in
            for e in list { c.yield(e) }
            c.finish()
        }
    }
    func stopWorkshop() async throws { stops += 1 }
    func setWorkshopModel(_ id: String) async throws {}
    func newWorkshop() async throws {}
}

private func snap(_ messages: [WorkshopMessage], job: WorkshopJob? = nil) -> WorkshopSnapshot {
    WorkshopSnapshot(messages: messages, job: job, model: "claude-subscription-opus-4-8",
                     choices: [WorkshopChoice(id: "claude-subscription-opus-4-8", label: "1 号 · Opus 4.8", account: 1, web_search: true),
                               WorkshopChoice(id: "deepseek:deepseek-v4-pro", label: "DeepSeek · v4-pro", account: 0, web_search: false)],
                     quota: ["1": ["session": WorkshopQuotaWindow(used: 8, reset_at: 0), "week": WorkshopQuotaWindow(used: 4, reset_at: 0)]])
}

private func msg(_ id: Int, _ role: String, _ content: String) -> WorkshopMessage {
    WorkshopMessage(id: id, role: role, origin: "her", content: content, trace: [], to_ke: "", model: "", status: "done",
                    created_at: "2026-11-03 12:00:00")
}

@MainActor
final class WorkshopStoreTests: XCTestCase {
    func testSendFollowsTheTurnUntilDoneThenShowsTheReply() async throws {
        let api = FakeWorkshop(snapshot: snap([]))
        var text = WorkshopEvent(kind: .text, seq: 1); text.text = "查了一下"
        var tool = WorkshopEvent(kind: .tool, seq: 2); tool.tool = "Bash"; tool.text = "看日志"
        var done = WorkshopEvent(kind: .done, seq: 3); done.status = "done"
        await api.setEvents([text, tool, done])
        let store = WorkshopStore(api: api)
        await store.load()
        await api.setSnapshot(snap([msg(1, "user", "卡了"), msg(2, "assistant", "是数据库锁了")]))
        let ok = await store.send("卡了")
        XCTAssertTrue(ok)
        for _ in 0..<50 where store.running { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(store.running)
        XCTAssertEqual(store.messages.map(\.content), ["卡了", "是数据库锁了"])
        let sent = await api.sent
        XCTAssertEqual(sent, ["卡了"])
    }

    func testQuotaLineSaysDeepSeekCannotSearch() async {
        let api = FakeWorkshop(snapshot: snap([]))
        let store = WorkshopStore(api: api)
        await store.load()
        XCTAssertEqual(store.quotaLine, "1 号 · 5 小时 8% · 本周 4%")
        await store.setModel("deepseek:deepseek-v4-pro")
        XCTAssertTrue(store.quotaLine.contains("不能联网搜索"))
    }

    func testEventJSONParsesToolBriefAndDone() {
        let tool = WorkshopEvent(json: #"{"type":"tool","tool":"Read","brief":"runtime/db.py","id":"t1","seq":4}"#)
        XCTAssertEqual(tool?.kind, .tool)
        XCTAssertEqual(tool?.text, "runtime/db.py")
        XCTAssertEqual(tool?.seq, 4)
        let done = WorkshopEvent(json: #"{"type":"done","status":"error","error":"出错了","seq":9}"#)
        XCTAssertEqual(done?.status, "error")
        XCTAssertEqual(done?.error, "出错了")
        XCTAssertNil(WorkshopEvent(json: "不是 json"))
    }
}
