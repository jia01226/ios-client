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

    @MainActor func testTimeSpaceKeepsCompletedRemindersInCalendarAndAllowsPartialRefresh() async {
        CompanionStub.handler = { request in
            switch request.url!.lastPathComponent {
            case "anniversaries": return (503, "{}")
            case "schedule": return (200, #"{"current":[{"id":1,"text":"待处理","scheduled_for":"2020-01-01 08:00:00","status":"pending","outcome":"","outcome_label":"","due":true}],"history":[{"id":2,"text":"已提醒","scheduled_for":"2020-01-02 08:00:00","status":"completed","outcome":"sent","outcome_label":"已发出","due":true}]}"#)
            default: return (200, "[]")
            }
        }
        let store = TimeDataStore(api: api())
        await store.refresh()
        XCTAssertEqual(store.pending.count, 1)
        XCTAssertEqual(store.reminders.count, 2)
        XCTAssertTrue(store.anniversaries.isEmpty)
        XCTAssertEqual(store.error, "纪念日没有刷新成功，请重试。")
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

    func testDateParsingRejectsImpossibleDatesAndUsesChinaTime() {
        XCTAssertNil(CompanionDate.parse("2026-02-30"))
        let date = CompanionDate.parse("2026-09-09 00:30:00")!
        XCTAssertEqual(ISO8601DateFormatter().string(from: date), "2026-09-08T16:30:00Z")
    }
}
