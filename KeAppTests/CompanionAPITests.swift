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

final class CompanionAPITests: XCTestCase {
    private func api() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CompanionStub.self]
        return APIClient(baseURL: URL(string: "https://example.invalid/ke-test2")!, configuration: configuration)
    }

    override func tearDown() { CompanionStub.handler = nil; super.tearDown() }

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

    @MainActor func testRefreshKeepsPendingOverdueRemindersAndUnknownShiftLabels() async throws {
        CompanionStub.handler = { request in
            switch request.url!.lastPathComponent {
            case "anniversaries": return (200, #"[{"id":1,"name":"相识","date":"2024-02-29","emoji":"","days":924}]"#)
            case "schedule": return (200, #"{"current":[{"id":9,"text":"仍待处理","scheduled_for":"2020-01-01 08:00:00","status":"pending","outcome":"blocked","outcome_label":"等待","due":true}],"history":[]}"#)
            default:
                let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = CompanionDate.calendar.timeZone
                return (200, "[{\"date\":\"\(formatter.string(from: .now))\",\"shift\":\"备班\",\"note\":\"\"}]")
            }
        }
        let model = UsViewModel(api: api())
        await model.refresh()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.activeReminders.count, 1)
        XCTAssertEqual(model.thisWeek.first?.label, "备班")
        XCTAssertEqual(model.anniversaries.first?.isYearly, true)
        CompanionStub.handler = { _ in (503, #"{"error":"暂时不可用"}"#) }
        await model.refresh()
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.activeReminders.count, 1)
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

    func testDateParsingRejectsImpossibleDatesAndUsesChinaTime() {
        XCTAssertNil(CompanionDate.parse("2026-02-30"))
        let date = CompanionDate.parse("2026-09-09 00:30:00")!
        XCTAssertEqual(ISO8601DateFormatter().string(from: date), "2026-09-08T16:30:00Z")
    }
}
