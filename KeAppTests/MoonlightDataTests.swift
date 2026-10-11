import XCTest
@testable import KeApp

@MainActor
final class MoonlightDataTests: XCTestCase {
    func testDiaryDateLabelUsesSameDayAsRailAcrossTimeZones() throws {
        let date = try XCTUnwrap(CompanionDate.parse("2026-10-08 00:00:00"))
        XCTAssertEqual(KeDiaryPage.dateLabel(date, format: "M月d日"), "10月8日")
    }
    func testDiaryGroupsKePagesByDayAndNeverIncludesLockedOrUserContent() {
        func row(_ id: Int, _ author: String, _ content: String, _ locked: Bool = false) -> RemoteDiary {
            RemoteDiary(id: id, title: "一页", content: content, author: author, mood: nil, created_at: "2026-10-07 23:59:00", locked_hidden: locked, comments: 0)
        }
        let pages = KeDiaryPage.collect([row(1, "柯", "第一段"), row(2, "柯", "PRIVATE", true), row(3, "佳佳", "USER"), row(4, "柯", "第二段")])
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages.first?.content, "第一段\n\n第二段")
        XCTAssertEqual(CompanionDate.calendar.component(.day, from: pages[0].date), 7)
    }
    func testLegacyDiaryAPIRepeatingSamePageStopsWithoutDuplicating() async {
        let api = RepeatedDiaryAPI()
        let store = KeDiaryStore(api: api)
        await store.load()
        XCTAssertEqual(api.calls, 2)
        XCTAssertFalse(store.historyIsComplete)
        XCTAssertEqual(store.pages.count, 1)
        XCTAssertEqual(store.pages[0].content.components(separatedBy: "\n\n").count, 50)
    }

}

private final class RepeatedDiaryAPI: KeDiaryAPI {
    var calls = 0
    func fetchDiaries(query: String, offset: Int, limit: Int) async throws -> [RemoteDiary] {
        calls += 1
        return (0..<50).map { RemoteDiary(id: $0, title: "日记", content: "第\($0)段", author: "柯", mood: nil, created_at: "2026-10-07 20:00:00", locked_hidden: false, comments: 0) }
    }
}
