import XCTest
@testable import KeApp

/// 123：日记页的「夜里」——怎么认服务器给的、点评怎么发、先改后存没存上怎么退回去、记住上次看的哪一栏。

private final class NightStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, text) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private func nightBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open(); defer { stream.close() }
    var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

/// 假的服务器：每次点评都先挂着，测试自己决定它什么时候、成功还是失败。
/// holdFetch 打开时，拉一页也先挂着——那一页是请求到的时候服务器上的样子，回来得晚就是旧的
private actor FakeNight: NightDiaryService {
    var pages: [Int?: [RemoteNight]] = [:]
    private(set) var fetches: [Int?] = []
    private(set) var comments: [[String]] = []
    private var gates: [CheckedContinuation<RemoteNight, Error>] = []
    private var holdFetch = false
    private var fetchGates: [CheckedContinuation<Void, Never>] = []

    func setPage(before: Int?, _ list: [RemoteNight]) { pages[before] = list }
    func setHoldFetch(_ on: Bool) { holdFetch = on }
    var waitingCount: Int { gates.count }
    var fetchWaitingCount: Int { fetchGates.count }
    func releaseFetch() { fetchGates.removeFirst().resume() }

    func fetchNight(limit: Int, beforeID: Int?) async throws -> [RemoteNight] {
        fetches.append(beforeID)
        let page = pages[beforeID] ?? []
        if holdFetch { await withCheckedContinuation { fetchGates.append($0) } }
        return page
    }
    func commentNight(id: Int, rating: NightRating?, comment: String) async throws -> RemoteNight {
        comments.append([String(id), rating?.rawValue ?? "", comment])
        return try await withCheckedThrowingContinuation { gates.append($0) }
    }
    func finishFirst(_ result: Result<RemoteNight, Error>) { gates.removeFirst().resume(with: result) }
}

/// 认数据、和服务器说话、记住哪一栏（不放在主线程上：假服务器的回调在 URLSession 的线程上跑）
final class NightDiaryTests: XCTestCase {
    private func api() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NightStub.self]
        return APIClient(baseURL: URL(string: "https://example.invalid/ke-test2")!, configuration: configuration)
    }

    // MARK: 认数据

    func testDecodingToleratesMissingFieldsUnknownKindAndBrokenRows() throws {
        let json = #"""
        {"entries": [
          {"id": 12, "kind": "together", "kind_label": "一起的", "tag": "雨夜", "content": "第一行\n\n第二行", "created_at": "2026-10-19 00:40:00",
           "rating": "love", "comment": "喜欢这句", "commented_at": "2026-10-19 08:00:00", "deleted": 0},
          {"id": 11, "kind": "solo", "content": "只有一行", "created_at": "2026-10-18 23:05:00"},
          {"id": "10", "kind": "dream", "content": "认不出来的种类", "created_at": "2026-10-18 22:00:00", "rating": "wow", "deleted": true},
          {"kind": "fantasy", "content": "没有 id 的这条跳过"},
          null,
          {"id": 9, "kind": "fantasy", "kind_label": "", "tag": null, "comment": null, "created_at": "2026-10-17 21:00:00"}
        ]}
        """#
        let rows = try JSONDecoder().decode(NightPage.self, from: Data(json.utf8)).entries
        XCTAssertEqual(rows.map(\.id), [12, 11, 10, 9])

        XCTAssertEqual(rows[0].nightKind, .together)
        XCTAssertEqual(rows[0].nightRating, .love)
        XCTAssertEqual(NightText.kindLine(rows[0]), "一起的 · 雨夜")
        XCTAssertEqual(NightText.preview(rows[0].content), "第一行 第二行")

        XCTAssertEqual(rows[1].tag, "")
        XCTAssertEqual(rows[1].comment, "")
        XCTAssertEqual(rows[1].rating, "")
        XCTAssertNil(rows[1].nightRating)
        XCTAssertEqual(rows[1].kindText, "他一个人", "没给 kind_label 就按 kind 自己写")
        XCTAssertEqual(NightText.kindLine(rows[1]), "他一个人", "没有 tag 不留「 · 」")

        XCTAssertNil(rows[2].nightKind)
        XCTAssertEqual(rows[2].kindText, "夜里")
        XCTAssertNil(rows[2].nightRating, "认不出来的评价当没点")
        XCTAssertTrue(rows[2].isDeleted)

        XCTAssertEqual(rows[3].kindText, "只是想")
        XCTAssertEqual(rows[3].tag, "")
        XCTAssertEqual(rows[3].content, "")
        XCTAssertEqual(NightText.preview(rows[3].content), "……")

        let empty = try JSONDecoder().decode(NightPage.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.entries.isEmpty)
    }

    // MARK: 和服务器说话

    func testFetchSendsLimitAndBeforeID() async throws {
        var seen: [[String: String]] = []
        NightStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/night")
            XCTAssertEqual(request.httpMethod, "GET")
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            seen.append(Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }))
            return (200, #"{"entries":[{"id":3,"kind":"solo","kind_label":"他一个人","tag":"","content":"嗯","created_at":"2026-10-19 01:00:00","rating":"","comment":"","commented_at":"","deleted":0}]}"#)
        }
        let first = try await api().fetchNight(limit: 100, beforeID: nil)
        XCTAssertEqual(first.map(\.id), [3])
        _ = try await api().fetchNight(limit: 100, beforeID: 42)
        XCTAssertEqual(seen.count, 2)
        XCTAssertEqual(seen.first, ["limit": "100"])
        XCTAssertEqual(seen.last, ["limit": "100", "before_id": "42"])
    }

    func testCommentSendsRatingAndOneLineCommentTogether() async throws {
        var bodies: [[String: String]] = []
        NightStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/night/7/comment")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let object = try JSONSerialization.jsonObject(with: XCTUnwrap(nightBody(request)))
            let fields = try XCTUnwrap(object as? [String: String])
            bodies.append(fields)
            return (200, #"{"ok":true,"entry":{"id":7,"kind":"solo","kind_label":"他一个人","tag":"","content":"嗯","created_at":"2026-10-19 01:00:00","rating":"\#(fields["rating"] ?? "")","comment":"\#(fields["comment"] ?? "")","commented_at":"2026-10-19 08:00:00","deleted":0}}"#)
        }
        let saved = try await api().commentNight(id: 7, rating: .love, comment: "  想你\n再写一次  ")
        XCTAssertEqual(bodies.last, ["rating": "love", "comment": "想你 再写一次"])
        XCTAssertEqual(saved.nightRating, .love)
        XCTAssertEqual(saved.comment, "想你 再写一次")

        // 取消评价、清掉那句话：两个都发 ""
        _ = try await api().commentNight(id: 7, rating: nil, comment: "")
        XCTAssertEqual(bodies.last, ["rating": "", "comment": ""])
        XCTAssertEqual(NightComment.body(rating: .meh, comment: "a\r\nb")["comment"] as? String, "a b")
    }

    func testMissingEntryIs404WithChineseMessage() async {
        NightStub.handler = { _ in (404, #"{"error":"not_found"}"#) }
        do {
            _ = try await api().commentNight(id: 99, rating: .ok, comment: "")
            XCTFail("找不到的那条不能算存上了")
        } catch {
            guard case APIError.badStatus(404, _) = error else { return XCTFail("应该是 404：\(error)") }
            XCTAssertEqual(NightText.saveError(error), "这一条找不到了，可能柯收起来了。")
        }
        XCTAssertEqual(NightText.saveError(APIError.transport(URLError(.notConnectedToInternet))), "网络没接稳，没存上。再点一次试试。")
        XCTAssertEqual(NightText.saveError(APIError.invalidResponse), "没存上，再试一次。")
    }

    // MARK: 界面验收用的样例

    #if DEBUG
    func testPreviewFixtureServesNightPageAndEchoesComments() throws {
        let base = URL(string: "https://example.invalid/ke-test2")!
        var get = URLRequest(url: base.appendingPathComponent("api/night").appending(queryItems: [URLQueryItem(name: "limit", value: "100")]))
        get.httpMethod = "GET"
        let (code, text) = try XCTUnwrap(NightPreviewData.response(for: get))
        XCTAssertEqual(code, 200)
        let rows = try JSONDecoder().decode(NightPage.self, from: Data(text.utf8)).entries
        XCTAssertGreaterThanOrEqual(rows.count, 4)
        XCTAssertEqual(Set(rows.compactMap(\.nightKind)), Set(NightKind.allCases), "一起的 / 他一个人 / 只是想都有")
        XCTAssertTrue(rows.contains { $0.nightKind == nil }, "还有一条认不出来的种类")
        XCTAssertTrue(rows.contains { !$0.comment.isEmpty } && rows.contains { $0.comment.isEmpty })

        let older = URLRequest(url: base.appendingPathComponent("api/night").appending(queryItems: [URLQueryItem(name: "before_id", value: "1")]))
        let (_, olderText) = try XCTUnwrap(NightPreviewData.response(for: older))
        XCTAssertTrue(try JSONDecoder().decode(NightPage.self, from: Data(olderText.utf8)).entries.isEmpty)

        let target = try XCTUnwrap(rows.first { $0.comment.isEmpty })
        var post = URLRequest(url: base.appendingPathComponent("api/night/\(target.id)/comment"))
        post.httpMethod = "POST"
        post.httpBody = try JSONSerialization.data(withJSONObject: NightComment.body(rating: .ok, comment: "样例 一句"))
        let (postCode, postText) = try XCTUnwrap(NightPreviewData.response(for: post))
        XCTAssertEqual(postCode, 200)
        let reply = try JSONDecoder().decode(NightCommentReply.self, from: Data(postText.utf8))
        XCTAssertEqual(reply.entry?.id, target.id)
        XCTAssertEqual(reply.entry?.nightRating, .ok)
        XCTAssertEqual(reply.entry?.comment, "样例 一句")
        // 还原，别的测试看到的还是原样
        post.httpBody = try JSONSerialization.data(withJSONObject: NightComment.body(rating: nil, comment: ""))
        _ = NightPreviewData.response(for: post)

        var missing = URLRequest(url: base.appendingPathComponent("api/night/99999/comment"))
        missing.httpMethod = "POST"
        missing.httpBody = Data("{}".utf8)
        XCTAssertEqual(NightPreviewData.response(for: missing)?.0, 404)
        XCTAssertNil(NightPreviewData.response(for: URLRequest(url: base.appendingPathComponent("api/diary"))), "别的路不管")
    }
    #endif

    // MARK: 记住上次看的哪一栏

    func testDiaryTabRemembersChoiceButOpeningCardLandsOnDiary() {
        XCTAssertEqual(DiaryTab.diary.rawValue, "diary", "存在本机的值不能改名")
        XCTAssertEqual(DiaryTab.night.rawValue, "night")
        XCTAssertEqual(DiaryTab.allCases.map(\.label), ["日记", "夜里"])
        XCTAssertNotEqual(DiaryTab.storageKey, "notebook.purse.tab")

        XCTAssertEqual(DiaryTab.current(saved: "night", pinnedToDiary: false), .night)
        XCTAssertEqual(DiaryTab.current(saved: "diary", pinnedToDiary: false), .diary)
        XCTAssertEqual(DiaryTab.current(saved: "night", pinnedToDiary: true), .diary, "从「爸爸开锁了」点进来一定是日记")
        XCTAssertEqual(DiaryTab.current(saved: "", pinnedToDiary: false), .diary)
        XCTAssertEqual(DiaryTab.current(saved: "garden", pinnedToDiary: false), .diary)

        // 照 @AppStorage 的样子来回存一遍
        let defaults = UserDefaults(suiteName: "night-diary-tests")!
        defer { defaults.removePersistentDomain(forName: "night-diary-tests") }
        defaults.set(DiaryTab.night.rawValue, forKey: DiaryTab.storageKey)
        XCTAssertEqual(DiaryTab.current(saved: defaults.string(forKey: DiaryTab.storageKey) ?? "", pinnedToDiary: false), .night)
    }
}

/// 先改后存、翻页、一天一块：NightStore 在主线程上
@MainActor final class NightStoreTests: XCTestCase {
    private func waitFor(_ count: Int, on fake: FakeNight) async {
        for _ in 0..<5000 {
            if await fake.waitingCount >= count { return }
            await Task.yield()
        }
        XCTFail("等不到第 \(count) 次点评发出去")
    }

    private func until(_ what: String, _ condition: () async -> Bool) async {
        for _ in 0..<5000 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("等不到：\(what)")
    }

    private static let base = RemoteNight(id: 5, kind: "solo", content: "嗯", created_at: "2026-10-19 01:00:00")
    private static func server(rating: String = "", comment: String = "", at: String = "x") -> RemoteNight {
        var e = base; e.rating = rating; e.comment = comment; e.commented_at = at; return e
    }
    private func loadedStore(_ fake: FakeNight) async -> NightStore {
        await fake.setPage(before: nil, [Self.base])
        let store = NightStore(service: fake)
        store.announce = { _ in }
        await store.load()
        return store
    }

    // MARK: 先改后存

    func testOptimisticCommentRollsBackWhenSaveFails() async throws {
        let fake = FakeNight()
        await fake.setPage(before: nil, [RemoteNight(id: 3, kind: "solo", content: "嗯", created_at: "2026-10-19 01:00:00")])
        let store = NightStore(service: fake)
        await store.load()
        XCTAssertEqual(store.entries.map(\.id), [3])
        XCTAssertTrue(store.loaded)

        let task = Task { await store.save(id: 3, rating: .love, comment: "再来") }
        await waitFor(1, on: fake)
        XCTAssertEqual(store.entries[0].rating, "love", "不等服务器，先改上")
        XCTAssertEqual(store.entries[0].comment, "再来")
        XCTAssertTrue(store.saving.contains(3))

        await fake.finishFirst(.failure(APIError.transport(URLError(.timedOut))))
        let outcome = await task.value
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(store.entries[0].rating, "", "没存上就退回去")
        XCTAssertEqual(store.entries[0].comment, "")
        XCTAssertEqual(store.errors[3], "网络没接稳，没存上。再点一次试试。")
        XCTAssertFalse(store.saving.contains(3))
        let sent = await fake.comments
        XCTAssertEqual(sent, [["3", "love", "再来"]])
    }

    func testLatestTapWinsAndFailureFallsBackToLastConfirmed() async throws {
        let fake = FakeNight()
        let store = await loadedStore(fake)

        // 先点「喜欢」，还没回来又改成「一般」：一条一次只发一个，「一般」排着；第一次的失败不算数，不退回、不报错
        let first = Task { await store.save(id: 5, rating: .love, comment: "") }
        await waitFor(1, on: fake)
        let second = Task { await store.save(id: 5, rating: .ok, comment: "") }
        await until("「一般」先摆上") { store.entries[0].nightRating == .ok }
        let waitingBefore = await fake.waitingCount
        XCTAssertEqual(waitingBefore, 1, "前一个没回来，后一个不发")
        await fake.finishFirst(.failure(APIError.invalidResponse))
        let firstOutcome = await first.value
        XCTAssertEqual(firstOutcome, .superseded)
        XCTAssertEqual(store.entries[0].nightRating, .ok)
        XCTAssertNil(store.errors[5])
        await waitFor(1, on: fake)
        await fake.finishFirst(.success(Self.server(rating: "ok")))
        let secondOutcome = await second.value
        XCTAssertEqual(secondOutcome, .saved)
        XCTAssertEqual(store.entries[0].commented_at, "x", "最后用服务器回来的那份")
        XCTAssertTrue(store.saving.isEmpty)
        let sent = await fake.comments
        XCTAssertEqual(sent, [["5", "love", ""], ["5", "ok", ""]])

        // 先成功一次（不是最后一次），最后那次失败：退回到服务器确认过的那份，不是退回最早的
        let a = Task { await store.save(id: 5, rating: .love, comment: "一") }
        await waitFor(1, on: fake)
        let b = Task { await store.save(id: 5, rating: .meh, comment: "二") }
        await until("「二」先摆上") { store.entries[0].comment == "二" }
        await fake.finishFirst(.success(Self.server(rating: "love", comment: "一")))
        let aOutcome = await a.value
        XCTAssertEqual(aOutcome, .saved)
        XCTAssertEqual(store.entries[0].comment, "二", "后面那次还在路上，先摆后面那次")
        await waitFor(1, on: fake)
        await fake.finishFirst(.failure(APIError.badStatus(500, "")))
        let bOutcome = await b.value
        XCTAssertEqual(bOutcome, .failed)
        XCTAssertEqual(store.entries[0].nightRating, .love)
        XCTAssertEqual(store.entries[0].comment, "一")
        XCTAssertEqual(store.errors[5], "没存上，再试一次。")
    }

    /// 前面那次后成功、后面那次先失败：以前屏幕退回最早的样子，服务器却存着「喜欢」。现在一次只发一个，对得上
    func testEarlierSuccessThenLaterFailureShowsWhatTheServerKept() async throws {
        let fake = FakeNight()
        let store = await loadedStore(fake)
        let a = Task { await store.save(id: 5, rating: .love, comment: "") }
        await waitFor(1, on: fake)
        let b = Task { await store.save(id: 5, rating: .ok, comment: "") }
        await until("「一般」先摆上") { store.entries[0].nightRating == .ok }
        await fake.finishFirst(.success(Self.server(rating: "love")))
        let aOutcome = await a.value
        XCTAssertEqual(aOutcome, .saved)
        await waitFor(1, on: fake)
        await fake.finishFirst(.failure(APIError.transport(URLError(.notConnectedToInternet))))
        let bOutcome = await b.value
        XCTAssertEqual(bOutcome, .failed)
        XCTAssertEqual(store.entries[0].nightRating, .love, "服务器存的是「喜欢」，屏幕上也是")
        XCTAssertNotNil(store.errors[5])
    }

    /// 连点好几下：排着的那几次让给最后一次，只发第一次和最后一次
    func testRapidTapsWhileOneIsInFlightSendOnlyTheLast() async throws {
        let fake = FakeNight()
        let store = await loadedStore(fake)
        let a = Task { await store.save(id: 5, rating: .love, comment: "") }
        await waitFor(1, on: fake)
        let b = Task { await store.save(id: 5, rating: .ok, comment: "") }
        await until("「一般」先摆上") { store.entries[0].nightRating == .ok }
        let c = Task { await store.save(id: 5, rating: .meh, comment: "") }
        let bOutcome = await b.value
        XCTAssertEqual(bOutcome, .superseded, "后面又点了，排着的那次不用等前面回来就让掉")
        XCTAssertEqual(store.entries[0].nightRating, .meh)
        await fake.finishFirst(.success(Self.server(rating: "love")))
        _ = await a.value
        await waitFor(1, on: fake)
        await fake.finishFirst(.success(Self.server(rating: "meh")))
        let cOutcome = await c.value
        XCTAssertEqual(cOutcome, .saved)
        XCTAssertEqual(store.entries[0].nightRating, .meh)
        let sent = await fake.comments
        XCTAssertEqual(sent, [["5", "love", ""], ["5", "meh", ""]])
        XCTAssertTrue(store.saving.isEmpty)
    }

    /// 刷新先发出去、点评后发先回来：晚回来的那一页是她点之前的，不能把存上的点评盖掉
    func testSlowRefreshDoesNotOverwriteASaveThatLandedMeanwhile() async throws {
        let fake = FakeNight()
        let store = await loadedStore(fake)
        await fake.setHoldFetch(true)
        let refresh = Task { await store.load() }
        await until("刷新发出去") { await fake.fetchWaitingCount == 1 }
        let save = Task { await store.save(id: 5, rating: .love, comment: "好") }
        await waitFor(1, on: fake)
        await fake.finishFirst(.success(Self.server(rating: "love", comment: "好")))
        _ = await save.value
        XCTAssertTrue(store.saving.isEmpty)
        await fake.releaseFetch()
        await refresh.value
        XCTAssertEqual(store.entries[0].nightRating, .love)
        XCTAssertEqual(store.entries[0].comment, "好")

        // 下一次刷新（点评之后才发的）照服务器的来
        await fake.setHoldFetch(false)
        await fake.setPage(before: nil, [Self.server(rating: "ok", comment: "别处改的")])
        await store.load()
        XCTAssertEqual(store.entries[0].comment, "别处改的")
    }

    // MARK: 她写的那句话

    /// 写了一句点「好」，还没回来又点「喜欢」，两次都没存上：那句话放回框里，读屏念一声
    func testFailedRatingAfterPendingCommentPutsHerSentenceBack() async throws {
        let fake = FakeNight()
        let store = await loadedStore(fake)
        var spoken: [String] = []
        store.announce = { spoken.append($0) }
        store.drafts[5] = "  她写的一句 "
        let send = Task { await store.send(5) }
        await waitFor(1, on: fake)
        XCTAssertEqual(store.entries[0].comment, "她写的一句")
        XCTAssertFalse(store.editing.contains(5))
        let rate = Task { await store.rate(5, .love) }
        await until("「喜欢」先摆上") { store.entries[0].nightRating == .love }
        await fake.finishFirst(.failure(APIError.transport(URLError(.notConnectedToInternet))))
        let sendOutcome = await send.value
        XCTAssertEqual(sendOutcome, .superseded, "让给后面那次，不算存上")
        XCTAssertNotNil(store.drafts[5], "还没定，她的字不清")
        await waitFor(1, on: fake)
        let sent = await fake.comments
        XCTAssertEqual(sent.last, ["5", "love", "她写的一句"], "评价带着那句话一起发")
        await fake.finishFirst(.failure(APIError.transport(URLError(.notConnectedToInternet))))
        let rateOutcome = await rate.value
        XCTAssertEqual(rateOutcome, .failed)
        XCTAssertEqual(store.entries[0].comment, "", "退回服务器那份")
        XCTAssertEqual(store.drafts[5], "她写的一句", "她写的放回框里")
        XCTAssertTrue(store.editing.contains(5))
        XCTAssertEqual(spoken, ["网络没接稳，没存上。再点一次试试。"])
    }

    func testSendClearsDraftOnlyWhenSavedAndLeavesANewEditAlone() async throws {
        let fake = FakeNight()
        let store = await loadedStore(fake)
        var spoken: [String] = []
        store.announce = { spoken.append($0) }

        store.drafts[5] = "第一句"
        let first = Task { await store.send(5) }
        await waitFor(1, on: fake)
        await fake.finishFirst(.success(Self.server(comment: "第一句")))
        let firstOutcome = await first.value
        XCTAssertEqual(firstOutcome, .saved)
        XCTAssertNil(store.drafts[5])
        XCTAssertFalse(store.editing.contains(5))

        // 存的时候她又点了「改」在写：回来以后框里她新写的不动
        store.drafts[5] = "第二句"
        let second = Task { await store.send(5) }
        await waitFor(1, on: fake)
        store.startEditing(store.entries[0])
        store.drafts[5] = "第二句还没写完"
        await fake.finishFirst(.success(Self.server(comment: "第二句")))
        _ = await second.value
        XCTAssertEqual(store.drafts[5], "第二句还没写完")
        XCTAssertTrue(store.editing.contains(5))

        // 只是点了「好」没改：不发
        store.drafts[5] = "第二句"
        let unchanged = await store.send(5)
        XCTAssertNil(unchanged)
        XCTAssertNil(store.drafts[5])
        let count = await fake.comments.count
        XCTAssertEqual(count, 2)

        // 改了没存上：放回框里、念一声
        store.drafts[5] = "第三句"
        let third = Task { await store.send(5) }
        await waitFor(1, on: fake)
        await fake.finishFirst(.failure(APIError.badStatus(404, "")))
        let thirdOutcome = await third.value
        XCTAssertEqual(thirdOutcome, .failed)
        XCTAssertEqual(store.entries[0].comment, "第二句")
        XCTAssertEqual(store.drafts[5], "第三句")
        XCTAssertTrue(store.editing.contains(5))
        XCTAssertEqual(spoken, ["这一条找不到了，可能柯收起来了。"])
    }

    /// 评价点了没存上：只是退回去、念一声；那句话本来就是存过的，不打开框
    func testFailedRatingAloneOnlyRollsBackAndAnnounces() async throws {
        let fake = FakeNight()
        await fake.setPage(before: nil, [Self.server(comment: "存过的")])
        let store = NightStore(service: fake)
        var spoken: [String] = []
        store.announce = { spoken.append($0) }
        await store.load()
        let rate = Task { await store.rate(5, .meh) }
        await waitFor(1, on: fake)
        XCTAssertEqual(store.entries[0].nightRating, .meh)
        await fake.finishFirst(.failure(APIError.unauthorized))
        let outcome = await rate.value
        XCTAssertEqual(outcome, .failed)
        XCTAssertNil(store.entries[0].nightRating)
        XCTAssertEqual(store.entries[0].comment, "存过的")
        XCTAssertFalse(store.editing.contains(5))
        XCTAssertNil(store.drafts[5])
        XCTAssertEqual(spoken, ["要重新登录一下才能存。"])
    }

    // MARK: 翻页

    func testPagingUsesOldestIDAndRefreshKeepsOlderPages() async throws {
        let fake = FakeNight()
        let firstPage = (101...200).reversed().map { RemoteNight(id: $0, created_at: "2026-10-19 01:00:00") }
        await fake.setPage(before: nil, firstPage)
        await fake.setPage(before: 101, [RemoteNight(id: 100, created_at: "2026-10-10 01:00:00"),
                                         RemoteNight(id: 99, created_at: "2026-10-09 01:00:00", deleted: 1),
                                         RemoteNight(id: 98, created_at: "2026-10-08 01:00:00")])
        let store = NightStore(service: fake)
        await store.load()
        XCTAssertEqual(store.entries.count, 100)
        XCTAssertFalse(store.reachedEnd, "满满一页，说明可能还有更早的")

        await store.loadMore()
        XCTAssertEqual(store.entries.suffix(2).map(\.id), [100, 98], "删掉的那条不摆")
        XCTAssertTrue(store.reachedEnd)
        let fetches = await fake.fetches
        XCTAssertEqual(fetches, [nil, 101])

        // 再拉第一页：多了一条新的、少了一条（150），翻出来的更早的那几条还留着
        var refreshed = firstPage.filter { $0.id != 150 }
        refreshed.insert(RemoteNight(id: 201, created_at: "2026-10-19 02:00:00"), at: 0)
        await fake.setPage(before: nil, Array(refreshed.prefix(100)))
        await store.load()
        XCTAssertEqual(store.entries.first?.id, 201)
        XCTAssertFalse(store.entries.contains { $0.id == 150 })
        XCTAssertEqual(store.entries.suffix(2).map(\.id), [100, 98])
        XCTAssertTrue(store.reachedEnd)

        // 第一页不满：服务器上就这些了，更早的那几条（可能已经删了）不再留着
        await fake.setPage(before: nil, [RemoteNight(id: 201, created_at: "2026-10-19 02:00:00"),
                                         RemoteNight(id: 200, created_at: "2026-10-19 01:00:00")])
        await store.load()
        XCTAssertEqual(store.entries.map(\.id), [201, 200])
        XCTAssertTrue(store.reachedEnd)
    }

    func testMergeKeepsLocalVersionWhileSaving() {
        let old = [RemoteNight(id: 4, rating: "love", comment: "本机刚改的"), RemoteNight(id: 3), RemoteNight(id: 1)]
        let page = [RemoteNight(id: 5), RemoteNight(id: 4), RemoteNight(id: 3, comment: "服务器的")]
        let merged = NightStore.merge(firstPage: page, into: old, keepingLocal: [4])
        XCTAssertEqual(merged.map(\.id), [5, 4, 3, 1])
        XCTAssertEqual(merged[1].comment, "本机刚改的")
        XCTAssertEqual(merged[2].comment, "服务器的")
        XCTAssertTrue(NightStore.merge(firstPage: [], into: old, keepingLocal: []).isEmpty, "服务器那边一条都没有了")
    }

    // MARK: 一天一块、日子怎么写

    func testDayGroupingAndDayLine() {
        let list = [RemoteNight(id: 4, created_at: "2026-10-19 01:00:00"), RemoteNight(id: 3, created_at: "2026-10-19 00:10:00"),
                    RemoteNight(id: 2, created_at: "2026-10-18 23:00:00")]
        let days = NightText.days(list)
        XCTAssertEqual(days.map(\.0), ["2026-10-19", "2026-10-18"])
        XCTAssertEqual(days[0].1.map(\.id), [4, 3])
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 10, day: 19, hour: 12).date!
        XCTAssertEqual(NightText.dayLine("2026-10-19", now: now), "10月 · 周一")
        XCTAssertEqual(NightText.dayLine("2025-12-31", now: now), "2025年12月 · 周三")
        XCTAssertEqual(KeDiaryListView.time("2026-10-19 01:05:00"), "01:05")
    }
}
