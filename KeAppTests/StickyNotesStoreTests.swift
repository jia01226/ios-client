import XCTest
@testable import KeApp

@MainActor final class StickyNotesStoreTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "Sticky89." + UUID().uuidString)! }
    private func note(_ id: String, author: StickyNote.Author = .ai, acked: Bool = false) -> StickyNote {
        StickyNote(id: id, author: author, content: "匿名提醒", created_at: "2026-10-12", acked: acked)
    }
    func testLegacyDecodeDefaultsToUnacknowledged() throws {
        let value = try JSONDecoder().decode(StickyNote.self, from: Data(#"{"id":"a","author":"ai","content":"test","created_at":"2026"}"#.utf8))
        XCTAssertFalse(value.acked)
        XCTAssertNil(value.acked_at)
    }
    func testOnlyAIRemindersAndDraftBytesUnchanged() async throws {
        let d = defaults()
        let draft = try JSONEncoder().encode([note("draft", author: .user)])
        d.set(draft, forKey: "moonlight.notes.drafts.main")
        let api = Sticky89Fake([note("user", author: .user), note("ke")])
        let store = StickyNotesStore(api: api, scope: "main", defaults: d)
        await store.load()
        let result = await store.acknowledge(note("user", author: .user))
        XCTAssertFalse(result)
        XCTAssertEqual(store.all.map(\.id), ["ke"])
        XCTAssertEqual(d.data(forKey: "moonlight.notes.drafts.main"), draft)
        XCTAssertEqual(api.writes.count, 0)
    }
    func testAckRestoreSharedBetweenViewsAndServerAuthoritativeAfterReinstall() async {
        let d = defaults()
        let api = Sticky89Fake([note("ke")])
        let us = StickyNotesStore(api: api, scope: "main", defaults: d)
        let drawer = StickyNotesStore(api: api, scope: "main", defaults: d)
        await us.load()
        await us.acknowledge(note("ke"))
        XCTAssertTrue(us.all.isEmpty)
        XCTAssertEqual(drawer.archived.map(\.id), ["ke"])
        let reinstalled = StickyNotesStore(api: api, scope: "main", defaults: defaults())
        await reinstalled.load()
        XCTAssertEqual(reinstalled.archived.map(\.id), ["ke"])
        await drawer.restore(note("ke"))
        XCTAssertEqual(us.all.map(\.id), ["ke"])
        XCTAssertEqual(api.writes.map(\.1), [true, false])
    }
    func testPartialMigrationClearsOnlySuccessfulIDsAndRetriesFailedOne() async {
        let d = defaults()
        let key = "moonlight.notes.drafts.main.archived"
        d.set(["a", "b", "missing"], forKey: key)
        let api = Sticky89Fake([note("a"), note("b")])
        api.failingID = "b"
        let store = StickyNotesStore(api: api, scope: "main", defaults: d)
        await store.load()
        XCTAssertEqual(Set(d.stringArray(forKey: key) ?? []), ["b", "missing"])
        XCTAssertNotNil(store.status)
        api.failingID = nil
        await store.load()
        XCTAssertEqual(d.stringArray(forKey: key), ["missing"])
        XCTAssertEqual(api.writes.filter { $0.0 == "a" }.count, 1)
        XCTAssertEqual(store.archived.count, 2)
    }
    func testFailedMutationDoesNotHideOrRestoreNote() async {
        let api = Sticky89Fake([note("a"), note("b", acked: true)])
        let store = StickyNotesStore(api: api, scope: "main", defaults: defaults())
        await store.load()
        api.failingID = "a"
        let acked = await store.acknowledge(note("a"))
        XCTAssertFalse(acked)
        XCTAssertEqual(store.all.map(\.id), ["a"])
        api.failingID = "b"
        let restored = await store.restore(note("b"))
        XCTAssertFalse(restored)
        XCTAssertEqual(store.archived.map(\.id), ["b"])
    }
    func testOfflineLoadRetainsCacheAndOtherScopeIsIsolated() async {
        let d = defaults()
        let api = Sticky89Fake([note("a")])
        let store = StickyNotesStore(api: api, scope: "main", defaults: d)
        let other = StickyNotesStore(api: api, scope: "other", defaults: d)
        await store.load(); await other.load()
        await store.acknowledge(note("a"))
        XCTAssertEqual(other.all.map(\.id), ["a"])
        api.failFetch = true
        let restarted = StickyNotesStore(api: api, scope: "main", defaults: d)
        await restarted.load()
        XCTAssertEqual(restarted.archived.map(\.id), ["a"])
        XCTAssertNotNil(restarted.status)
    }
}
private final class Sticky89Fake: StickyNotesAPI {
    var rows: [StickyNote]
    var writes: [(String, Bool)] = []
    var failingID: String?
    var failFetch = false
    init(_ rows: [StickyNote]) { self.rows = rows }
    func fetchStickyNotes() async throws -> [StickyNote] {
        if failFetch { throw URLError(.notConnectedToInternet) }
        return rows
    }
    func setStickyNoteAcknowledged(id: String, acknowledged: Bool) async throws {
        if failingID == id { throw URLError(.notConnectedToInternet) }
        writes.append((id, acknowledged))
        if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].acked = acknowledged }
    }
}
