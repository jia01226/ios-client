import XCTest
@testable import KeApp

@MainActor
final class MoonlightDataTests: XCTestCase {
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
    func testNoteWriteFailureSurvivesRestartAndRetryKeepsSameID() async {
        let suite = "MoonNotes." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = NotesFake()
        let store = StickyNotesStore(api: api, scope: "test", defaults: defaults)
        await store.save("  记得带钥匙  ")
        XCTAssertEqual(store.drafts.count, 1)
        XCTAssertEqual(store.all.first?.content, "记得带钥匙")
        let restored = StickyNotesStore(api: api, scope: "test", defaults: defaults)
        XCTAssertEqual(restored.drafts.first?.id, store.drafts.first?.id)
        api.fail = false
        await restored.save(restored.drafts[0].content, editing: restored.drafts[0])
        XCTAssertEqual(Set(api.ids).count, 1)
        XCTAssertTrue(restored.drafts.isEmpty)
        XCTAssertNil(restored.status)
        let ke = StickyNote(id: "ke", author: .ai, content: "柯的", created_at: "2026-10-07")
        await restored.save("不能改柯的内容", editing: ke)
        XCTAssertEqual(api.ids.count, 2)
    }
}

private final class RepeatedDiaryAPI: KeDiaryAPI {
    var calls = 0
    func fetchDiaries(query: String, offset: Int, limit: Int) async throws -> [RemoteDiary] {
        calls += 1
        return (0..<50).map { RemoteDiary(id: $0, title: "日记", content: "第\($0)段", author: "柯", mood: nil, created_at: "2026-10-07 20:00:00", locked_hidden: false, comments: 0) }
    }
}
private final class NotesFake: StickyNotesAPI {
    var fail = true
    var ids: [String] = []
    func fetchStickyNotes() async throws -> [StickyNote] { [] }
    func saveStickyNote(id: String, content: String) async throws -> StickyNote {
        ids.append(id)
        if fail { throw URLError(.notConnectedToInternet) }
        return StickyNote(id: id, author: .user, content: content, created_at: "2026-10-07")
    }
    func deleteStickyNote(id: String) async throws {}
}
