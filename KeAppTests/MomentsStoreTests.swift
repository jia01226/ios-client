import XCTest
@testable import KeApp

@MainActor
final class MomentsStoreTests: XCTestCase {
    private func makeDefaults() -> (String, UserDefaults) {
        let suite = "MomentsTests." + UUID().uuidString
        return (suite, UserDefaults(suiteName: suite)!)
    }
    private func store(_ api: MomentsFake, defaults: UserDefaults, scope: String = "test1") -> MomentsStore {
        MomentsStore(api: api, scope: scope, defaults: defaults)
    }
    func testKePostsAndCommentsCannotBeEditedOrDeletedEvenIfCallerForgesAuthor() async {
        let (suite, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = MomentsFake(); let store = store(api, defaults: defaults); await store.load()
        assertAsyncFalse(await store.edit(api.rows[0], content: "changed"))
        assertAsyncFalse(await store.delete(api.rows[0]))
        assertAsyncFalse(await store.editComment(api.rows[0].comments[0], content: "changed"))
        assertAsyncFalse(await store.deleteComment(api.rows[0].comments[0]))
        let forged = RemoteMoment(id: 1, author: "user", content: "", image: nil, created_at: "", user_liked: 0, ai_liked: 0, comments: [])
        assertAsyncFalse(await store.delete(forged))
        XCTAssertTrue(api.writes.isEmpty)
    }
    func testOwnPostAndCommentMutationsUseCorrectIdentifiers() async {
        let (suite, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = MomentsFake(); let store = store(api, defaults: defaults); await store.load()
        let own = api.rows[1]; let comment = own.comments[0]
        assertAsyncTrue(await store.edit(own, content: "  revised  "))
        assertAsyncTrue(await store.editComment(comment, content: "  reply  "))
        assertAsyncTrue(await store.deleteComment(comment))
        assertAsyncTrue(await store.delete(own))
        XCTAssertEqual(api.writes, ["edit:2:revised", "edit-comment:22:reply", "delete-comment:22", "delete:2"])
    }
    func testImageOnlyPostAndLikeAreSupportedButEmptyPostIsRejected() async {
        let (suite, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = MomentsFake(); let store = store(api, defaults: defaults); await store.load()
        assertAsyncFalse(await store.publish(content: "  ", image: ""))
        assertAsyncTrue(await store.publish(content: "", image: "/uploads/a.jpg"))
        await store.like(api.rows[0])
        XCTAssertEqual(api.writes, ["post::/uploads/a.jpg", "like:1:true"])
    }
    func testConfirmedWriteWithFailedRefreshDoesNotInviteDuplicatePublication() async {
        let (suite, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = MomentsFake(); let store = store(api, defaults: defaults); await store.load()
        api.readFails = true
        assertAsyncTrue(await store.publish(content: "draft", image: ""))
        XCTAssertEqual(api.writes.count, 1)
        XCTAssertEqual(store.moments.count, 2)
        XCTAssertEqual(store.error, "已保存，列表暂时没有刷新成功，请下拉重试。")
        api.writeFails = true
        assertAsyncFalse(await store.publish(content: "draft two", image: ""))
        XCTAssertNotNil(store.error)
    }
    func testActivityIsOnlyAcknowledgedAfterSuccessfulListAndPersistsPerScope() async {
        let (suite, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = MomentsFake(); let first = store(api, defaults: defaults)
        await first.refreshActivity(); XCTAssertTrue(first.hasUnread)
        api.readFails = true
        await first.load(); XCTAssertTrue(first.hasUnread)
        api.readFails = false
        await first.load(); XCTAssertFalse(first.hasUnread)
        let restarted = store(api, defaults: defaults); await restarted.refreshActivity(); XCTAssertFalse(restarted.hasUnread)
        let other = store(api, defaults: defaults, scope: "test2"); await other.refreshActivity(); XCTAssertTrue(other.hasUnread)
        api.activity = MomentsActivity(last_ke_activity_at: "2026-10-11 15:00:00", waiting: true)
        await restarted.refreshActivity(); XCTAssertTrue(restarted.hasUnread)
        XCTAssertEqual(restarted.pollInterval, 5_000_000_000)
        api.statusFails = true
        await restarted.refreshActivity(); XCTAssertTrue(restarted.hasUnread)
    }
    func testNewActivityArrivingDuringListReadIsNotMarkedSeen() async {
        let (suite, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = MomentsFake(); let store = store(api, defaults: defaults)
        api.onRead = { api.activity = MomentsActivity(last_ke_activity_at: "2026-10-11 16:00:00", waiting: false) }
        await store.load()
        await store.refreshActivity()
        XCTAssertTrue(store.hasUnread)
    }
    func testWriteInFlightRejectsDuplicatePublication() async {
        let (suite, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = MomentsFake(); let store = store(api, defaults: defaults); await store.load()
        var resumeWrite: CheckedContinuation<Void, Never>?
        api.beforeWrite = { await withCheckedContinuation { resumeWrite = $0 } }
        let write = Task { await store.publish(content: "once", image: "") }
        while resumeWrite == nil { await Task.yield() }
        XCTAssertTrue(store.saving)
        assertAsyncFalse(await store.publish(content: "twice", image: ""))
        resumeWrite?.resume()
        assertAsyncTrue(await write.value)
        XCTAssertEqual(api.writes, ["post:once:"])
    }
}

// Async values are evaluated before XCTest's non-concurrent assertion autoclosure.
private func assertAsyncTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(value, file: file, line: line)
}
private func assertAsyncFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(value, file: file, line: line)
}

private final class MomentsFake: MomentsAPI {
    var rows: [RemoteMoment] = [
        RemoteMoment(id: 1, author: "ke", content: "柯的动态", image: nil, created_at: "2026-10-11 12:00:00", user_liked: 0, ai_liked: 0,
            comments: [RemoteMomentComment(id: 11, author: "ke", content: "柯的评论", created_at: "2026-10-11 12:00:00")]),
        RemoteMoment(id: 2, author: "user", content: "自己的动态", image: nil, created_at: "2026-10-11 12:00:00", user_liked: 0, ai_liked: 1,
            comments: [RemoteMomentComment(id: 22, author: "user", content: "自己的评论", created_at: "2026-10-11 12:00:00")])
    ]
    var activity = MomentsActivity(last_ke_activity_at: "2026-10-11 12:00:00", waiting: false)
    var readFails = false, writeFails = false, statusFails = false
    var writes: [String] = []
    var onRead: (() -> Void)?
    var beforeWrite: (() async -> Void)?
    func fetchMoments() async throws -> [RemoteMoment] {
        if readFails { throw URLError(.notConnectedToInternet) }; onRead?(); return rows
    }
    func fetchMomentsActivity() async throws -> MomentsActivity {
        if statusFails { throw URLError(.notConnectedToInternet) }; return activity
    }
    func record(_ value: String) async throws {
        await beforeWrite?()
        if writeFails { throw URLError(.notConnectedToInternet) }; writes.append(value)
    }
    func addMoment(content: String, image: String) async throws { try await record("post:\(content):\(image)") }
    func setMomentLike(id: Int, liked: Bool) async throws { try await record("like:\(id):\(liked)") }
    func addMomentComment(id: Int, content: String) async throws { try await record("comment:\(id):\(content)") }
    func editMoment(id: Int, content: String) async throws { try await record("edit:\(id):\(content)") }
    func deleteMoment(id: Int) async throws { try await record("delete:\(id)") }
    func editMomentComment(id: Int, content: String) async throws { try await record("edit-comment:\(id):\(content)") }
    func deleteMomentComment(id: Int) async throws { try await record("delete-comment:\(id)") }
}
