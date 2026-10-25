import XCTest
@testable import KeApp

/// 136：荷包、食单、药盒——没接上不一直转圈、连着点不吞、编辑框存上才关、打勾先改上没记上再退回。

/// 假的小本子服务器：写的时候可以先挂着，测试自己决定什么时候、成功还是失败
private actor FakeBook: NotebookAPI {
    var taken = false
    var owedDone = 0
    var failFetch = false
    var holdWrites = false
    /// 下一次写直接失败（不挂着）
    var failNextWrite: Error?
    private(set) var sent: [String] = []
    private(set) var fetches = 0
    private var gates: [CheckedContinuation<Void, Error>] = []

    func set(failFetch: Bool) { self.failFetch = failFetch }
    func set(holdWrites: Bool) { self.holdWrites = holdWrites }
    func failNext(_ error: Error) { failNextWrite = error }
    var waiting: Int { gates.count }
    func finishFirst(_ error: Error? = nil) {
        let gate = gates.removeFirst()
        if let error { gate.resume(throwing: error) } else { gate.resume() }
    }

    func fetchNotebook() async throws -> NotebookSnapshot {
        fetches += 1
        if failFetch { throw APIError.transport(URLError(.notConnectedToInternet)) }
        let json = """
        {"today":"2026-10-25",
         "purse":{"month":"2026-10","cap_cents":300000,"spent_cents":0,"left_cents":300000,"spends":[],"asks":[],"savings":[]},
         "menu":{"meals":[],"owed":[{"id":7,"kind":"owe","title":"火锅","done":\(owedDone),"author":"ke"}]},
         "meds":{"rx":[{"id":3,"kind":"rx","title":"维生素","when":"早上","done":0,"author":"me"}],
                 "today":{"早上":{"taken":\(taken),"author":null}},"order":["早上"],"log":[]},
         "verse":null}
        """
        return try JSONDecoder().decode(NotebookSnapshot.self, from: Data(json.utf8))
    }
    func createNotebookItem(kind: String, fields: [String: Any]) async throws -> NotebookItem {
        sent.append("create \(kind) \(fields["title"] as? String ?? "")")
        try await gate()
        return try JSONDecoder().decode(NotebookItem.self, from: Data(#"{"id":99,"kind":"spend","title":"x","done":0,"author":"me"}"#.utf8))
    }
    func updateNotebookItem(id: Int, fields: [String: Any]) async throws -> NotebookItem {
        let done = fields["done"] as? Bool
        sent.append("update \(id)" + (done.map { " done \($0)" } ?? ""))
        try await gate()
        if let done { owedDone = done ? 1 : 0 }
        return try JSONDecoder().decode(NotebookItem.self, from: Data(#"{"id":7,"kind":"owe","title":"火锅","done":0,"author":"ke"}"#.utf8))
    }
    func deleteNotebookItem(id: Int) async throws {
        sent.append("delete \(id)")
        try await gate()
    }
    func setNotebookDose(when: String, taken: Bool) async throws {
        sent.append("dose \(when) \(taken)")
        try await gate()
        self.taken = taken
    }
    func setNotebookCap(yuan: Double) async throws {
        sent.append("cap \(yuan)")
        try await gate()
    }
    private func gate() async throws {
        if let error = failNextWrite { failNextWrite = nil; throw error }
        guard holdWrites else { return }
        try await withCheckedThrowingContinuation { gates.append($0) }
    }
}

@MainActor final class NotebookStoreTests: XCTestCase {
    private let offline = APIError.transport(URLError(.timedOut))
    private func store(_ fake: FakeBook) -> NotebookStore {
        NotebookStore(api: APIClient(baseURL: URL(string: "https://example.invalid/ke-test")!), book: fake)
    }
    private func spend(_ item: NotebookItem? = nil) -> NotebookDraft {
        NotebookDraft(kind: "spend", item: item, heading: "记一笔", fields: [(.title, "买了什么")])
    }
    private func until(_ what: String, _ condition: () async -> Bool) async {
        for _ in 0..<500 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("等不到：\(what)")
    }

    func testLoadFailureOffersRetryInsteadOfSpinningForever() async {
        let fake = FakeBook()
        await fake.set(failFetch: true)
        let book = store(fake)
        await book.load()
        XCTAssertNil(book.snapshot)
        XCTAssertTrue(book.loadFailed, "拉不到要让页面换成「点这里再试」")
        XCTAssertNil(book.banner, "还没有上次的可看，大按钮说就够了")

        await fake.set(failFetch: false)
        await book.retry()
        XCTAssertNotNil(book.snapshot)
        XCTAssertFalse(book.loadFailed)

        // 有上次的、这次没拉到：标题下说一声，旁边能再试
        await fake.set(failFetch: true)
        await book.load()
        XCTAssertNotNil(book.snapshot, "拉不到也不清空上次的")
        XCTAssertEqual(book.banner, "小本子暂时没接上，先看上次记的。")
        XCTAssertTrue(book.canRetry)
        await fake.set(failFetch: false)
        await book.retry()
        XCTAssertNil(book.banner)
    }

    func testEditorOnlyClosesAfterTheSaveLands() async {
        let fake = FakeBook()
        let book = store(fake)
        await book.load()

        await fake.failNext(offline)
        let failed = await book.save(spend(), fields: ["title": "奶茶"])
        XCTAssertEqual(failed, "没存上，再点一次保存。")

        await fake.failNext(APIError.badStatus(400, "金额看不懂"))
        let reason = await book.save(spend(), fields: ["title": "奶茶"])
        XCTAssertEqual(reason, "没存上：金额看不懂", "服务器说了原因就照给她看")

        let fetchesBefore = await fake.fetches
        let saved = await book.save(spend(), fields: ["title": "奶茶"])
        XCTAssertNil(saved)
        let fetchesAfter = await fake.fetches
        XCTAssertEqual(fetchesAfter, fetchesBefore + 1, "存上了整本刷新一次")
        XCTAssertNil(book.notice)

        await fake.failNext(offline)
        let item = book.snapshot!.menu.owed[0]
        let notDeleted = await book.delete(item)
        XCTAssertEqual(notDeleted, "没删掉，再点一次。")
        let sent = await fake.sent
        XCTAssertEqual(sent, ["create spend 奶茶", "create spend 奶茶", "create spend 奶茶", "delete 7"])
    }

    func testSavedButRefreshFailedSaysSo() async {
        let fake = FakeBook()
        let book = store(fake)
        await book.load()
        await fake.set(failFetch: true)
        let saved = await book.save(spend(), fields: ["title": "面包"])
        XCTAssertNil(saved, "服务器存上了，框子照样关")
        XCTAssertEqual(book.notice, "存上了，只是页面还没刷新，下拉再看看。")
        XCTAssertTrue(book.canRetry)
    }

    func testTapsWhileBusyQueueUpInsteadOfBeingDropped() async {
        let fake = FakeBook()
        let book = store(fake)
        await book.load()
        await fake.set(holdWrites: true)

        let first = Task { await book.save(self.spend(), fields: ["title": "奶茶"]) }
        await until("第一笔发出去") { await fake.waiting == 1 }
        XCTAssertTrue(book.busy)
        let second = Task { await book.save(self.spend(), fields: ["title": "面包"]) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let sentWhileFirstPending = await fake.sent
        XCTAssertEqual(sentWhileFirstPending, ["create spend 奶茶"], "前一笔没回来，后一笔排着")

        await fake.finishFirst()
        await until("第二笔接着发") {
            let waiting = await fake.waiting, count = await fake.sent.count
            return waiting == 1 && count == 2
        }
        await fake.finishFirst()
        let a = await first.value, b = await second.value
        XCTAssertNil(a)
        XCTAssertNil(b)
        let sent = await fake.sent
        XCTAssertEqual(sent, ["create spend 奶茶", "create spend 面包"], "两笔都发了，一笔不吞")
        XCTAssertFalse(book.busy)
    }

    func testDoseCheckShowsAtOnceAndGoesBackWhenNotSaved() async {
        let fake = FakeBook()
        let book = store(fake)
        await book.load()
        await fake.set(holdWrites: true)

        let tap = Task { await book.setDose("早上", taken: true) }
        await until("发出去") { await fake.waiting == 1 }
        XCTAssertTrue(book.doseTaken("早上"), "不等服务器，先打上勾")
        XCTAssertFalse(book.snapshot!.meds.today["早上"]!.taken)

        await fake.finishFirst(offline)
        await tap.value
        XCTAssertFalse(book.doseTaken("早上"), "没记上就退回去")
        XCTAssertEqual(book.notice, "早上的药没记上，再点一次。")

        // 再点一次成功：勾留着，那句话收起
        let again = Task { await book.setDose("早上", taken: true) }
        await until("又发出去") { await fake.waiting == 1 }
        XCTAssertNil(book.notice)
        await fake.finishFirst()
        await again.value
        XCTAssertTrue(book.doseTaken("早上"))
        XCTAssertTrue(book.snapshot!.meds.today["早上"]!.taken, "服务器那份也是吃了")
        XCTAssertTrue(book.checking.isEmpty)
    }

    func testDoubleTapEndsWhereSheLeftIt() async {
        let fake = FakeBook()
        let book = store(fake)
        await book.load()
        await fake.set(holdWrites: true)

        // 点了「吃了」又马上点回「还没吃」：两下都发，照顺序
        let first = Task { await book.setDose("早上", taken: true) }
        await until("第一下发出去") { await fake.waiting == 1 }
        let second = Task { await book.setDose("早上", taken: !book.doseTaken("早上")) }
        await until("第二下先画上") { !book.doseTaken("早上") }

        // 第一下没成功：后面还有一下，不退回、不报错
        await fake.finishFirst(offline)
        await first.value
        XCTAssertFalse(book.doseTaken("早上"))
        XCTAssertNil(book.notice)
        await until("第二下发出去") { await fake.waiting == 1 }
        await fake.finishFirst()
        await second.value
        XCTAssertFalse(book.doseTaken("早上"))
        XCTAssertNil(book.notice)
        let sent = await fake.sent
        XCTAssertEqual(sent, ["dose 早上 true", "dose 早上 false"])
    }

    func testCheckSavedButNotRefreshedKeepsHerTick() async {
        let fake = FakeBook()
        let book = store(fake)
        await book.load()
        await fake.set(failFetch: true)
        await book.setDose("早上", taken: true)
        XCTAssertTrue(book.doseTaken("早上"), "存上了只是没刷新，勾不能掉回去")
        XCTAssertEqual(book.notice, "存上了，只是页面还没刷新，下拉再看看。")
        await fake.set(failFetch: false)
        await book.retry()
        XCTAssertTrue(book.checking.isEmpty, "拉到了就交回服务器那份")
        XCTAssertTrue(book.doseTaken("早上"))
    }

    func testOwedAndCapFailuresSayWhichThing() async {
        let fake = FakeBook()
        let book = store(fake)
        await book.load()
        let owed = book.snapshot!.menu.owed[0]

        await book.setOwed(owed, done: true)
        XCTAssertTrue(book.owedDone(book.snapshot!.menu.owed[0]))

        await fake.failNext(offline)
        await book.setOwed(book.snapshot!.menu.owed[0], done: false)
        XCTAssertTrue(book.owedDone(book.snapshot!.menu.owed[0]), "没改上，圈还是划着")
        XCTAssertEqual(book.notice, "「火锅」没改上，再点一次。")

        await fake.failNext(APIError.serverMessage("上限太大了"))
        await book.setCap(yuan: 3000)
        XCTAssertEqual(book.notice, "每月上限没改上：上限太大了")
        let sent = await fake.sent
        XCTAssertEqual(sent, ["update 7 done true", "update 7 done false", "cap 3000.0"])
    }
}
