import XCTest
@testable import KeApp

private final class CompanionStub: URLProtocol {
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

private func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

final class CompanionAPITests: XCTestCase {
    func testTarotShufflePickContractAndIdempotentRetry() async throws {
        let dealJSON = #"{"deal_id":"locked-7","deck_size":78,"spread":"three","spread_name":"三张","positions":["过去","现在","未来"]}"#
        CompanionStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/tarot/shuffle")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.httpShouldHandleCookies)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody(request)!) as? [String: String])
            XCTAssertEqual(body, ["spread": "three", "question": "匿名问题"])
            return (200, dealJSON)
        }
        let client = api()
        let deal = try await client.shuffleTarot(question: "匿名问题", spread: "three")
        var requests: [Data] = []
        var fail = true
        CompanionStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/tarot/pick")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.httpShouldHandleCookies)
            let bytes = try XCTUnwrap(requestBody(request)); requests.append(bytes)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual(body["deal_id"] as? String, "locked-7")
            XCTAssertEqual(body["picks"] as? [Int], [5, 40, 77])
            if fail { throw URLError(.timedOut) }
            let cards = ["过去", "现在", "未来"].enumerated().map { index, position in
                ["position": position, "name": "card", "cn": "牌", "type": "Major", "reversed": index == 1, "image": "card.png"] as [String: Any]
            }
            let result: [String: Any] = ["id": 9, "question": "匿名问题", "spread": "three", "spread_name": "三张", "cards": cards]
            return (200, String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
        }
        do { _ = try await client.pickTarot(deal: deal, picks: [5, 40, 77]); XCTFail("Expected timeout") } catch { }
        fail = false
        let result = try await client.pickTarot(deal: deal, picks: [5, 40, 77])
        XCTAssertEqual(result.id, 9); XCTAssertTrue(result.cards[1].reversed)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: requests[0]) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: requests[1]) as? NSDictionary)
    }

    /// 122：「夜里」洗牌不带问题、22 张；选的序号只能在 0..<22；翻出来的牌带 night 三段
    func testTarotNightShufflePickContract() async throws {
        CompanionStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/tarot/shuffle")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody(request)!) as? [String: String])
            XCTAssertEqual(body, ["spread": "night", "question": ""])
            return (200, #"{"deal_id":"night-1","deck_size":22,"spread":"night","spread_name":"夜里","positions":["过去·身份","现在·关系","未来·玩法"]}"#)
        }
        let client = api()
        let deal = try await client.shuffleTarot(question: "", spread: "night")
        XCTAssertEqual(deal.deck_size, 22)
        var pickCount = 0
        CompanionStub.handler = { request in
            pickCount += 1
            XCTAssertEqual(request.url?.path, "/ke-test2/api/tarot/pick")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody(request)!) as? [String: Any])
            XCTAssertEqual(body["picks"] as? [Int], [0, 21, 7])
            let columns = [("relationship", "身份"), ("emotion", "关系"), ("play", "玩法")]
            let cards = ["过去·身份", "现在·关系", "未来·玩法"].enumerated().map { index, position in
                ["position": position, "name": "card", "cn": "牌", "type": "major", "reversed": index == 2, "image": "card.png",
                 "night": ["column": columns[index].0, "label": columns[index].1, "desc": "场景\(index)", "interpret": "解读\(index)"]] as [String: Any]
            }
            let result: [String: Any] = ["id": 31, "question": "", "spread": "night", "spread_name": "夜里", "cards": cards]
            return (200, String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
        }
        do { _ = try await client.pickTarot(deal: deal, picks: [0, 22, 7]); XCTFail("22 is outside the night deck") } catch { }
        XCTAssertEqual(pickCount, 0)
        let cast = try await client.pickTarot(deal: deal, picks: [0, 21, 7])
        XCTAssertEqual(cast.cards.map { $0.night?.label }, ["身份", "关系", "玩法"])
        XCTAssertEqual(cast.cards[2].night?.desc, "场景2"); XCTAssertTrue(cast.cards[2].reversed)
        XCTAssertEqual(cast.readingMessage(question: "不该带上"), "爸比，今晚抽了「夜里」。 [塔罗#31]")

        // 服务器若给夜里回了 78 张的牌堆，就当没准备好
        CompanionStub.handler = { _ in
            (200, #"{"deal_id":"night-2","deck_size":78,"spread":"night","spread_name":"夜里","positions":["过去·身份","现在·关系","未来·玩法"]}"#)
        }
        do { _ = try await client.shuffleTarot(question: "", spread: "night"); XCTFail("Expected invalid night deal") } catch { }
    }

    func testTarotExpiredDealDoesNotAutomaticallyReshuffle() async throws {
        let deal = TarotDeal(deal_id: .text("expired"), deck_size: 78, spread: "one", spread_name: "一张", positions: ["此刻"])
        var count = 0
        CompanionStub.handler = { request in
            count += 1
            XCTAssertEqual(request.url?.path, "/ke-test2/api/tarot/pick")
            return (400, #"{"error":"deal expired"}"#)
        }
        do { _ = try await api().pickTarot(deal: deal, picks: [0]); XCTFail("Expected expired deal error") } catch { }
        XCTAssertEqual(count, 1)
    }

    func testGardenAndStickyMutationContractsKeepCookieAndLinePrefix() async throws {
        CompanionStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/memory/garden")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.httpShouldHandleCookies)
            return (200, #"{"categories":[],"flowers":[]}"#)
        }
        _ = try await api().memoryGarden()
        for action in ["wither", "revive", "love"] {
            CompanionStub.handler = { request in
                XCTAssertEqual(request.url?.path, "/ke-test2/api/memory/garden/flower-7/\(action)")
                XCTAssertEqual(request.httpMethod, "POST")
                let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody(request)!) as? [String: Any])
                if action == "love" { XCTAssertEqual(fields["loved"] as? Bool, true) }
                if action == "wither" { XCTAssertEqual(fields["note"] as? String, "匿名更正") }
                return (200, #"{"ok":true}"#)
            }
            try await api().changeMemoryFlower(id: "flower-7", action: action,
                                             note: action == "wither" ? "匿名更正" : nil,
                                             loved: action == "love" ? true : nil)
        }
        for acknowledged in [true, false] {
            CompanionStub.handler = { request in
                XCTAssertEqual(request.url?.path, "/ke-test2/api/sticky-notes/" + (acknowledged ? "ack" : "unack"))
                XCTAssertEqual(request.httpMethod, "POST")
                let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody(request)!) as? [String: String])
                XCTAssertEqual(fields, ["id": "note-7"])
                return (200, #"{"ok":true}"#)
            }
            try await api().setStickyNoteAcknowledged(id: "note-7", acknowledged: acknowledged)
        }
    }

    func testMomentsActivityAndCommentRoutesMatchBackendContract() async throws {
        CompanionStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/moments/status")
            XCTAssertEqual(request.httpMethod, "GET")
            return (200, #"{"last_ke_activity_at":"2026-10-11 12:00:00","waiting":true}"#)
        }
        let activity = try await api().fetchMomentsActivity()
        XCTAssertTrue(activity.waiting)
        XCTAssertEqual(activity.last_ke_activity_at, "2026-10-11 12:00:00")
        CompanionStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/moments/comment/edit")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody(request)!) as? [String: Any])
            XCTAssertEqual(body["id"] as? Int, 7)
            XCTAssertEqual(body["content"] as? String, "new comment")
            return (200, #"{"ok":true}"#)
        }
        try await api().editMomentComment(id: 7, content: "new comment")
        CompanionStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/moments/comment/delete")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody(request)!) as? [String: Int])
            XCTAssertEqual(body, ["id": 7])
            return (200, #"{"ok":true}"#)
        }
        try await api().deleteMomentComment(id: 7)
    }

    func testMomentImageOnlyPublicationUsesUploadURLAndPrivateVisibility() async throws {
        CompanionStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/moments")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody(request)!) as? [String: String])
            XCTAssertEqual(body, ["content": "", "image": "/uploads/photo.jpg", "visibility": "private"])
            return (200, #"{"id":7,"session_id":9,"reply_due_at":"2026-10-11 12:00:00"}"#)
        }
        try await api().addMoment(content: "", image: "/uploads/photo.jpg")
    }

    func testMomentUploadImageReadKeepsSelectedLinePrefix() async throws {
        CompanionStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/uploads/photo.jpg")
            XCTAssertEqual(request.httpMethod, "GET")
            return (200, "image-bytes")
        }
        _ = try await api().fetchMomentImageData(at: "/uploads/photo.jpg")
        _ = try await api().fetchMomentImageData(at: "uploads/photo.jpg")
        _ = try await api().fetchMomentImageData(at: "https://example.invalid/ke-test2/uploads/photo.jpg")
    }

    private func api() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CompanionStub.self]
        return APIClient(baseURL: URL(string: "https://example.invalid/ke-test2")!, configuration: configuration)
    }

    override func tearDown() { CompanionStub.handler = nil; super.tearDown() }

    func testHutLetterUsesExistingSessionLineAndTextOnly() async throws {
        CompanionStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/hut/letter")
            XCTAssertEqual(request.httpMethod, "POST")
            let data = try XCTUnwrap(requestBody(request))
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
            XCTAssertEqual(fields, ["text": "这里想改一句"])
            return (200, "{\"ok\":true,\"id\":8}")
        }
        try await api().sendHutLetter(text: "这里想改一句")
    }

    /// 121：聊天记录里柯的消息带着服务器切好的气泡；她的消息不带。
    /// 这一项格式不对时当它没有，整页记录照样解析出来。
    func testChatHistoryCarriesServerBubbleSegments() async throws {
        CompanionStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/messages")
            XCTAssertEqual(request.httpMethod, "GET")
            return (200, #"""
            [
              {"id":1,"author":"user","content":"在吗","created_at":"2026-10-19 21:00:00"},
              {"id":2,"author":"assistant","content":"在。\n\n一直在。","created_at":"2026-10-19 21:00:05",
               "segments":["在。","一直在。"]},
              {"id":3,"author":"assistant","content":"旧的一条","created_at":"2026-10-19 21:01:00"},
              {"id":4,"author":"assistant","content":"坏掉的切法","created_at":"2026-10-19 21:02:00","segments":"oops"}
            ]
            """#)
        }
        let messages = try await api().fetchMessages(sessionID: 1)
        XCTAssertEqual(messages.map(\.serverID), [1, 2, 3, 4])
        XCTAssertNil(messages[0].segments)
        XCTAssertEqual(messages[1].segments, ["在。", "一直在。"])
        XCTAssertEqual(messages[1].bubbleSegments, ["在。", "一直在。"])
        XCTAssertNil(messages[2].segments)
        XCTAssertNil(messages[3].segments)
        XCTAssertEqual(messages[3].bubbleSegments, ["坏掉的切法"])
    }

    func testMissingPeriodEndEndpointFailsWithoutDeletingOrAddingAStart() async {
        CompanionStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/periods/end")
            let fields = try JSONSerialization.jsonObject(with: XCTUnwrap(requestBody(request))) as? [String: Any]
            XCTAssertEqual(fields?["id"] as? Int, 8)
            XCTAssertEqual(fields?["end_date"] as? String, "2026-10-07")
            XCTAssertNil(fields?["start_date"])
            return (404, "{\"error\":\"not deployed\"}")
        }
        do { try await api().endPeriod(id: 8, endDate: "2026-10-07"); XCTFail("Missing endpoint must remain a failure") }
        catch { }
    }

    func testReadsStayInsideSelectedLine() async throws {
        CompanionStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/schedule")
            return (200, #"{"current":[{"id":7,"text":"带资料","scheduled_for":"2026-09-09 08:00:00","status":"pending","outcome":"","outcome_label":"","due":true}],"history":[]}"#)
        }
        let schedule = try await api().fetchSchedule()
        XCTAssertEqual(schedule.current.first?.id, 7)
        XCTAssertTrue(schedule.current.first?.due == true)
    }

    func testServerRejectedWriteDoesNotSucceed() async throws {
        CompanionStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/ke-test2/api/shifts")
            return (200, #"{"ok":false,"error":"日期无效"}"#)
        }
        do {
            try await api().setShift(date: "bad-date", shift: "早班", note: "")
            XCTFail("Server rejection must remain a failure")
        } catch APIError.serverMessage(let message) { XCTAssertEqual(message, "日期无效") }
    }

    func testMalformedWriteReceiptDoesNotSucceed() async throws {
        CompanionStub.handler = { _ in (200, "{}") }
        do {
            try await api().addAnniversary(name: "相识", date: "2026-09-09")
            XCTFail("An empty receipt cannot confirm a save")
        } catch APIError.invalidResponse { }
    }

    func testDiarySearchEncodesQueryAndPagination() async throws {
        CompanionStub.handler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let values = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(request.url?.path, "/ke-test2/api/diary")
            XCTAssertEqual(values["query"], "月光 & 我")
            XCTAssertEqual(values["offset"], "50")
            XCTAssertEqual(values["limit"], "25")
            return (200, #"[{"id":8,"title":"月光","content":"正文","author":"柯","created_at":"2026-09-08 23:00:00","locked_hidden":false,"comments":0}]"#)
        }
        let rows = try await api().fetchDiaries(query: "月光 & 我", offset: 50, limit: 25)
        XCTAssertEqual(rows.map(\.id), [8])
    }

    func testArchiveHistoryStaysInsideSelectedLine() async throws {
        CompanionStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/history/archive")
            return (200, #"[{"id":1,"author":"user","content":"最开始","msg_type":"text","created_at":"2026-07-01 10:00:00"}]"#)
        }
        let rows = try await api().fetchArchivedMessages(query: "开始")
        XCTAssertEqual(rows.first?.content, "最开始")
    }

    func testCompanionRequestsCarryExistingHouseKey() async throws {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "example.invalid",
            .path: "/",
            .name: "ke_home",
            .value: "saved-house-key",
            .secure: "TRUE",
        ]))
        HTTPCookieStorage.shared.setCookie(cookie)
        defer { HTTPCookieStorage.shared.deleteCookie(cookie) }
        CompanionStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "ke_home=saved-house-key")
            return (200, "[]")
        }
        _ = try await api().fetchDiaries()
    }

    func testWebReadingAnnotationSendsOnlyCurrentExcerpt() async throws {
        CompanionStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/ke-test2/api/reading/web-annotate")
            let body = try XCTUnwrap(requestBody(request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(object["title"], "小王子")
            XCTAssertEqual(object["url"], "https://example.com/chapter-1")
            XCTAssertEqual(object["excerpt"], "只有这一小段")
            return (200, #"{"author":"柯","content":"这里我想陪你多停一会儿。"}"#)
        }
        let comment = try await api().annotateWebReading(
            title: "小王子", url: "https://example.com/chapter-1", excerpt: "只有这一小段"
        )
        XCTAssertEqual(comment.author, "柯")
        XCTAssertEqual(comment.content, "这里我想陪你多停一会儿。")
    }

    @MainActor func testUsHomeLoadsRealAnniversariesInsteadOfDemoDates() async {
        CompanionStub.handler = { request in
            switch request.url!.lastPathComponent {
            case "schedule": return (200, #"{"current":[],"history":[]}"#)
            case "anniversaries":
                return (200, #"[{"id":1,"name":"佳佳的生日","date":"2001-02-26"},{"id":2,"name":"柯的生日","date":"1992-10-26"},{"id":3,"name":"在一起的日子","date":"2026-06-25"},{"id":4,"name":"表白的日子","date":"2026-08-09"}]"#)
            default: return (404, "{}")
            }
        }
        let viewModel = UsViewModel(api: api())
        await viewModel.loadReminders()
        XCTAssertEqual(viewModel.anniversaries.map(\.title), ["表白的日子", "在一起的日子", "佳佳的生日", "柯的生日"])
        let dates = viewModel.anniversaries.map {
            let parts = CompanionDate.calendar.dateComponents([.year, .month, .day], from: $0.date)
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }
        XCTAssertEqual(dates, ["2026-08-09", "2026-06-25", "2001-02-26", "1992-10-26"])
    }

    /// 137：「管理日期」里另加的日子也出现在「我们」；删了就不见；她改过名的固定日子按上次对上的 id 认
    @MainActor
    func testUsHomeShowsDatesAddedInManageDates() async {
        let suite = "UsAnniversaryTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var rows = #"[{"id":1,"name":"佳佳的生日","date":"2001-02-26"},{"id":2,"name":"柯的生日","date":"1992-10-26"},{"id":3,"name":"在一起的日子","date":"2026-06-25"},{"id":4,"name":"表白的日子","date":"2026-08-09"},{"id":5,"name":"第一次通话","date":"2026-07-10"}]"#
        CompanionStub.handler = { request in
            switch request.url!.lastPathComponent {
            case "schedule": return (200, #"{"current":[],"history":[]}"#)
            case "anniversaries": return (200, rows)
            default: return (404, "{}")
            }
        }
        let viewModel = UsViewModel(defaults: defaults, api: api())
        await viewModel.loadReminders()
        XCTAssertEqual(viewModel.anniversaries.map(\.id), ["confession", "together", "mine", "ke", "server-5"])
        XCTAssertEqual(viewModel.anniversaries.last?.title, "第一次通话")
        XCTAssertEqual(viewModel.anniversaries.last?.isYearly, false)
        // 下次开 App 还没拉到时也先画上
        XCTAssertEqual(UsViewModel(defaults: defaults).anniversaries.last?.id, "server-5")
        // 「表白的日子」改了名、换了日子：还是那一格；「第一次通话」删了就不见
        rows = #"[{"id":1,"name":"佳佳的生日","date":"2001-02-26"},{"id":2,"name":"柯的生日","date":"1992-10-26"},{"id":3,"name":"在一起的日子","date":"2026-06-25"},{"id":4,"name":"第一次说喜欢","date":"2026-08-10"}]"#
        await viewModel.loadReminders()
        XCTAssertEqual(viewModel.anniversaries.map(\.id), ["confession", "together", "mine", "ke"])
        XCTAssertEqual(viewModel.anniversaries.first?.title, "第一次说喜欢")
        XCTAssertEqual(Calendar.current.component(.day, from: viewModel.anniversaries[0].date), 10)
        XCTAssertEqual(UsViewModel(defaults: defaults).anniversaries.count, 4)
    }

    func testDateParsingRejectsImpossibleDatesAndUsesChinaTime() {
        XCTAssertNil(CompanionDate.parse("2026-02-30"))
        let date = CompanionDate.parse("2026-09-09 00:30:00")!
        XCTAssertEqual(ISO8601DateFormatter().string(from: date), "2026-09-08T16:30:00Z")
    }
}
