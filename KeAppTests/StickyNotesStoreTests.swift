import XCTest
@testable import KeApp

@MainActor
final class StickyNotesStoreTests: XCTestCase {
    func testOnlyKeRemindersAreVisibleAndHistoricalDraftBytesStayUnchanged() async throws {
        let (suite, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacyDraft = note("draft", author: .user)
        let legacyData = try JSONEncoder().encode([legacyDraft])
        defaults.set(legacyData, forKey: "moonlight.notes.drafts.main")
        let api = StickyNotesReadFake([note("user", author: .user), note("ke")])
        let store = StickyNotesStore(api: api, scope: "main", defaults: defaults)

        await store.load()
        XCTAssertEqual(store.all.map(\.id), ["ke"])
        XCTAssertEqual(store.drafts, [legacyDraft])
        store.acknowledge(note("user", author: .user))
        XCTAssertTrue(store.archived.isEmpty)
        store.acknowledge(note("ke"))
        store.restore(note("ke"))
        await store.load()

        XCTAssertEqual(defaults.data(forKey: "moonlight.notes.drafts.main"), legacyData)
        XCTAssertEqual(store.drafts, [legacyDraft])
        XCTAssertEqual(api.fetchCalls, 2)
    }

    func testLocalAcknowledgementSurvivesReloadAndRestartAndCanBeRestored() async {
        let (suite, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let reminder = note("ke")
        let api = StickyNotesReadFake([reminder])
        let store = StickyNotesStore(api: api, scope: "main", defaults: defaults)
        await store.load()
        store.acknowledge(reminder)
        XCTAssertTrue(store.all.isEmpty)
        XCTAssertEqual(store.archived, [reminder])
        await store.load()
        XCTAssertEqual(store.archived, [reminder])

        let restarted = StickyNotesStore(api: api, scope: "main", defaults: defaults)
        XCTAssertTrue(restarted.all.isEmpty)
        XCTAssertEqual(restarted.archived, [reminder])
        restarted.restore(reminder)
        XCTAssertEqual(restarted.all, [reminder])
        XCTAssertTrue(restarted.archived.isEmpty)
        XCTAssertEqual(store.all, [reminder], "The other view updates immediately within the same scope.")
        XCTAssertEqual(StickyNotesStore(api: api, scope: "main", defaults: defaults).all, [reminder])
    }

    func testArchiveIsSharedWithinScopeAndIsolatedBetweenScopes() async {
        let (suite, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let reminder = note("shared-id")
        let api = StickyNotesReadFake([reminder])
        let us = StickyNotesStore(api: api, scope: "main", defaults: defaults)
        let drawer = StickyNotesStore(api: api, scope: "main", defaults: defaults)
        let otherLine = StickyNotesStore(api: api, scope: "compact", defaults: defaults)
        await us.load()
        await drawer.load()
        await otherLine.load()

        us.acknowledge(reminder)
        XCTAssertEqual(drawer.archived, [reminder])
        XCTAssertTrue(drawer.all.isEmpty)
        XCTAssertEqual(otherLine.all, [reminder])
        XCTAssertTrue(otherLine.archived.isEmpty)
        drawer.restore(reminder)
        XCTAssertEqual(us.all, [reminder])
    }

    func testFailedLoadPreservesCachedRemindersAndArchiveChoice() async {
        let (suite, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = note("first")
        let second = note("second")
        let api = StickyNotesReadFake([first, second])
        let store = StickyNotesStore(api: api, scope: "main", defaults: defaults)
        await store.load()
        store.acknowledge(first)
        api.failure = URLError(.notConnectedToInternet)
        let restarted = StickyNotesStore(api: api, scope: "main", defaults: defaults)
        await restarted.load()

        XCTAssertEqual(restarted.all, [second])
        XCTAssertEqual(restarted.archived, [first])
        XCTAssertNotNil(restarted.status)
        XCTAssertFalse(restarted.loading)
    }

    func testTemporaryMissingReminderDoesNotClearItsArchiveChoice() async {
        let (suite, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let reminder = note("ke")
        let api = StickyNotesReadFake([reminder])
        let store = StickyNotesStore(api: api, scope: "main", defaults: defaults)
        await store.load()
        store.acknowledge(reminder)
        api.rows = []
        await store.load()
        api.rows = [reminder]
        await store.load()
        XCTAssertEqual(store.archived, [reminder])
        XCTAssertTrue(store.all.isEmpty)
    }

    private func makeDefaults() -> (String, UserDefaults) {
        let suite = "StickyNotesTests." + UUID().uuidString
        return (suite, UserDefaults(suiteName: suite)!)
    }
    private func note(_ id: String, author: StickyNote.Author = .ai) -> StickyNote {
        StickyNote(id: id, author: author, content: "记得带钥匙。", created_at: "2026-10-07T20:00:00Z")
    }
}

private final class StickyNotesReadFake: StickyNotesAPI {
    var rows: [StickyNote]
    var failure: Error?
    var fetchCalls = 0
    init(_ rows: [StickyNote]) { self.rows = rows }
    func fetchStickyNotes() async throws -> [StickyNote] {
        fetchCalls += 1
        if let failure { throw failure }
        return rows
    }
}
