import XCTest
@testable import KeApp

private final class FakeLoveAPI: LoveLogAPI, @unchecked Sendable {
    var deleted: [Int] = []
    var fail = false
    func loveLog(month: String) async throws -> LoveLogMonth {
        if fail { throw APIError.invalidResponse }
        let json = #"{"month":"2026-10","days":{"2026-10-20":1,"2026-10-21":2},"month_count":3,"total":3,"items":[{"id":1,"day":"2026-10-20","at":"2026-10-21 20:27:54","source":"diary","note":"补的"},{"id":2,"day":"2026-10-21","at":"2026-10-21 22:10:00","source":"auto","note":""},{"id":3,"day":"2026-10-21","at":"2026-10-21 23:40:00","source":"ke","note":""}]}"#
        return try JSONDecoder().decode(LoveLogMonth.self, from: Data(json.utf8))
    }
    func deleteLove(id: Int) async throws { deleted.append(id) }
}

@MainActor final class LoveLogTests: XCTestCase {
    private func day(_ d: Int) -> Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: d))! }

    func testCalendarShowsCountsPerDayAndMonth() async {
        let defaults = UserDefaults(suiteName: "love-\(UUID().uuidString)")!
        let api = FakeLoveAPI(), store = LoveLogStore(api: api, defaults: defaults)
        await store.load(day(1))
        XCTAssertEqual(store.count(on: day(20)), 1)
        XCTAssertEqual(store.count(on: day(21)), 2)
        XCTAssertEqual(store.count(on: day(22)), 0)
        XCTAssertEqual(store.monthCount(day(5)), 3)
        XCTAssertEqual(store.items(on: day(21)).map(\.id), [2, 3])
        // 再打开时先画上次的，拉不到也不清空
        api.fail = true
        let again = LoveLogStore(api: api, defaults: defaults)
        XCTAssertEqual(again.count(on: day(21)), 2)
        await again.load(day(1))
        XCTAssertEqual(again.count(on: day(21)), 2)
        XCTAssertNil(again.error)
    }

    func testDeletingAskesTheServer() async {
        let api = FakeLoveAPI(), store = LoveLogStore(api: api, defaults: UserDefaults(suiteName: "love-\(UUID().uuidString)")!)
        await store.load(day(1))
        let ok = await store.delete(store.items(on: day(21))[0])
        XCTAssertTrue(ok)
        XCTAssertEqual(api.deleted, [2])
    }
}
