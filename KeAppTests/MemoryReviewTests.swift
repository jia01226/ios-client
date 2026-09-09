import XCTest
@testable import KeApp

actor ReviewTestService: MemoryReviewService {
    let backend = MemoryReviewFixtureService()
    var offline = false
    var loseReceipt = false
    var conflict = false
    var attempts: [ReviewOperation] = []
    func configure(offline: Bool = false, loseReceipt: Bool = false, conflict: Bool = false) {
        self.offline = offline; self.loseReceipt = loseReceipt; self.conflict = conflict
    }
    func reviewPending(offset: Int) async throws -> ReviewPage {
        if offline { throw URLError(.notConnectedToInternet) }
        return try await backend.reviewPending(offset: offset)
    }
    func submitReview(_ operation: ReviewOperation) async throws -> ReviewReceipt {
        attempts.append(operation)
        if offline { throw URLError(.notConnectedToInternet) }
        if conflict { throw APIError.badStatus(409, "这张卡已有新修改") }
        let receipt = try await backend.submitReview(operation)
        if loseReceipt { loseReceipt = false; throw URLError(.networkConnectionLost) }
        return receipt
    }
    func reviewStats() async throws -> ReviewStats { try await backend.reviewStats() }
    func reviewedFacts(offset: Int) async throws -> ReviewedFactsPage { try await backend.reviewedFacts(offset: offset) }
}

@MainActor
final class MemoryReviewTests: XCTestCase {
    var directory: URL!
    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }
    func store(_ api: ReviewTestService, line: ChatLine = .main) -> MemoryReviewStore {
        MemoryReviewStore(line: line, service: api, file: directory.appendingPathComponent(line.rawValue + ".json"), watchNetwork: false)
    }

    func testOfflineNoteAndDecisionSurviveRelaunchThenSync() async throws {
        let api = ReviewTestService()
        let first = store(api)
        await first.sync()
        let card = try XCTUnwrap(first.pending.first)
        await api.configure(offline: true)
        XCTAssertTrue(first.act(.note, on: card, note: "只是玩笑"))
        XCTAssertEqual(first.pending.count, 2)
        let annotated = try XCTUnwrap(first.pending.first)
        XCTAssertTrue(first.act(.accept, on: annotated, note: annotated.note))
        await first.sync()
        XCTAssertEqual(first.archive.outbox.count, 2)
        let reopened = store(api)
        XCTAssertEqual(reopened.archive.outbox.count, 2)
        XCTAssertEqual(reopened.pending.count, 1)
        await api.configure()
        await reopened.sync()
        XCTAssertEqual(reopened.archive.outbox.count, 0)
        XCTAssertEqual(reopened.archive.facts.first?.note, "只是玩笑")
    }

    func testLostReceiptUsesSameOperationAndUndoRestoresCard() async throws {
        let api = ReviewTestService()
        let viewModel = store(api)
        await viewModel.sync()
        let card = try XCTUnwrap(viewModel.pending.first)
        XCTAssertTrue(viewModel.act(.accept, on: card, note: ""))
        await api.configure(loseReceipt: true)
        await viewModel.sync()
        let id = try XCTUnwrap(viewModel.archive.outbox.first?.id)
        await viewModel.sync()
        let attempts = await api.attempts
        XCTAssertEqual(attempts.map(\.id), [id, id])
        XCTAssertEqual(viewModel.archive.facts.count, 1)
        viewModel.undo()
        await viewModel.sync()
        XCTAssertEqual(viewModel.pending.first?.id, card.id)
        XCTAssertTrue(viewModel.archive.facts.isEmpty)
        XCTAssertFalse(viewModel.canUndo)
    }

    func testDeferRequiresNoteAndCanReturnFromDeferredQueue() async throws {
        let api = ReviewTestService()
        let viewModel = store(api)
        await viewModel.sync()
        let card = try XCTUnwrap(viewModel.pending.first)
        XCTAssertFalse(viewModel.act(.defer, on: card, note: "  "))
        XCTAssertTrue(viewModel.act(.defer, on: card, note: "语境不确定"))
        await viewModel.sync()
        XCTAssertEqual(viewModel.pending.count, 1)
        XCTAssertEqual(viewModel.deferred.count, 1)
        let deferred = try XCTUnwrap(viewModel.deferred.first)
        XCTAssertTrue(viewModel.act(.reject, on: deferred, note: deferred.note))
        await viewModel.sync()
        XCTAssertTrue(viewModel.deferred.isEmpty)
        XCTAssertTrue(viewModel.archive.facts.isEmpty)
    }

    func testDraftAndWindowsPersistSeparately() async throws {
        let api = ReviewTestService()
        let main = store(api)
        await main.sync()
        let card = try XCTUnwrap(main.pending.first)
        main.saveDraft("还在考虑", for: card)
        let reopened = store(api)
        XCTAssertEqual(reopened.draft(for: card), "还在考虑")
        let other = store(api, line: .test2)
        XCTAssertTrue(other.archive.drafts.isEmpty)
        XCTAssertTrue(other.archive.cards.isEmpty)
    }

    func testConflictRetainsOperationAndTextUntilExplicitRecovery() async throws {
        let api = ReviewTestService()
        let viewModel = store(api)
        await viewModel.sync()
        let card = try XCTUnwrap(viewModel.pending.first)
        XCTAssertTrue(viewModel.act(.accept, on: card, note: "保留这句话"))
        await api.configure(conflict: true)
        await viewModel.sync()
        XCTAssertFalse(viewModel.canReview)
        XCTAssertEqual(viewModel.archive.outbox.count, 1)
        await api.configure()
        await viewModel.discardBlockedOperation()
        XCTAssertEqual(viewModel.archive.outbox.count, 0)
        XCTAssertEqual(viewModel.pending.count, 2)
        XCTAssertEqual(viewModel.draft(for: card), "保留这句话")
    }

    func testStorageFailureNeverAdvancesCard() async throws {
        let api = ReviewTestService()
        let viewModel = store(api)
        await viewModel.sync()
        let card = try XCTUnwrap(viewModel.pending.first)
        try FileManager.default.removeItem(at: directory)
        try Data("block directory".utf8).write(to: directory)
        XCTAssertFalse(viewModel.act(.accept, on: card, note: ""))
        XCTAssertEqual(viewModel.pending.first?.id, card.id)
        XCTAssertTrue(viewModel.archive.outbox.isEmpty)
    }

    func testChangeDraftAndOfflineOperationSurviveRelaunch() async throws {
        let api = ReviewTestService()
        let model = store(api)
        await model.sync()
        let card = try XCTUnwrap(model.pending.first)
        XCTAssertFalse(model.act(.changed, on: card, note: ""))
        model.saveChangeDraft(MemoryChangeDraft(fact: "现在喜欢草莓", when: "今年八月"), for: card)
        let reopened = store(api)
        XCTAssertEqual(reopened.changeDraft(for: card).fact, "现在喜欢草莓")
        await api.configure(offline: true)
        XCTAssertTrue(reopened.act(.changed, on: card, note: "不是过敏"))
        await reopened.sync()
        let again = store(api)
        XCTAssertEqual(again.archive.outbox.first?.new_fact, "现在喜欢草莓")
        XCTAssertEqual(again.archive.outbox.first?.changed_when, "今年八月")
        await api.configure()
        await again.sync()
        XCTAssertEqual(again.archive.facts.first?.fact, "现在喜欢草莓")
        again.undo()
        await again.sync()
        XCTAssertEqual(again.pending.first?.id, card.id)
    }

    func testDirectionAndThresholdIgnoreShortAndDiagonalDrags() {
        XCTAssertEqual(ReviewGesture.action(x: 120, y: 10), .accept)
        XCTAssertEqual(ReviewGesture.action(x: -120, y: 10), .reject)
        XCTAssertEqual(ReviewGesture.action(x: 10, y: -120), .defer)
        XCTAssertNil(ReviewGesture.action(x: 99, y: 0))
        XCTAssertNil(ReviewGesture.action(x: 110, y: 110))
        XCTAssertEqual(ReviewGesture.action(x: 0, y: 150), .changed)
    }
}
