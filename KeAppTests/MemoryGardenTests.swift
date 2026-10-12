import XCTest
@testable import KeApp

private func flower(_ id: Int, author: String = "ke", category: String = "约定", state: String = "bloom") throws -> MemoryFlower {
    let body: [String: Any] = ["id": id, "title": "匿名标题", "body": "我记得的匿名样例", "quotes": ["匿名原话"],
                              "category": category, "state": state, "author": author, "importance": 7,
                              "valence": 0.8, "loved": false]
    return try JSONDecoder().decode(MemoryFlower.self, from: JSONSerialization.data(withJSONObject: body))
}

private actor GardenFake: MemoryGardenAPI {
    var rows: [MemoryFlower]
    var fail = false
    var actions: [String] = []
    init(_ rows: [MemoryFlower]) { self.rows = rows }
    func failing(_ value: Bool) { fail = value }
    func memoryGarden() async throws -> MemoryGardenPage {
        if fail { throw URLError(.notConnectedToInternet) }
        return MemoryGardenPage(categories: ["旅行"], flowers: rows)
    }
    func changeMemoryFlower(id: String, action: String, note: String?, loved: Bool?) async throws {
        if fail { throw URLError(.notConnectedToInternet) }
        actions.append(action)
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        switch action {
        case "wither": rows[i].state = "withered"
        case "revive": rows[i].state = "bloom"
        case "love": rows[i].loved = loved ?? false
        default: break
        }
    }
}

@MainActor final class MemoryGardenTests: XCTestCase {
    func testDefaultsHideOtherAuthorsAndWitheredButKeepArchivedPetals() async throws {
        let rows = try [flower(1), flower(2, author: "other"), flower(3, state: "fallen"), flower(4, state: "withered")]
        let store = MemoryGardenStore(api: GardenFake(rows))
        await store.load()
        XCTAssertEqual(store.visible(includeOthers: false).map(\.id), ["1", "3"])
        XCTAssertEqual(store.visible(includeOthers: true).map(\.id), ["1", "2", "3"])
        XCTAssertTrue(store.categories.contains("旅行"))
    }
    func testEachIDProducesExactlyOneNodeIncluding647Memories() throws {
        let rows = try (0..<647).map { try flower($0) }
        for scene in MemoryScene.allCases {
            let nodes = MemoryFlowerLayout.nodes(rows, scene: scene)
            XCTAssertEqual(nodes.count, 647)
            XCTAssertEqual(Set(nodes.map { $0.flower.id }).count, 647)
            XCTAssertTrue(nodes.allSatisfy { CGRect(origin: .zero, size: MemoryFlowerLayout.size).contains($0.frame) })
            XCTAssertEqual(nodes.map(\.frame), MemoryFlowerLayout.nodes(rows, scene: scene).map(\.frame))
        }
        XCTAssertTrue(MemoryFlowerLayout.nodes([], scene: .moon).isEmpty)
    }
    func testDuplicateServerIDsNeverCreateExtraFlowers() async throws {
        let value = try flower(1)
        let store = MemoryGardenStore(api: GardenFake([value, value]))
        await store.load()
        XCTAssertEqual(store.flowers.count, 1)
    }
    func testFlowersKeepTheirPlaceWhenAnotherMemoryArrives() throws {
        let one = try flower(1)
        for scene in MemoryScene.allCases {
            let before = MemoryFlowerLayout.nodes([one], scene: scene)[0]
            let after = MemoryFlowerLayout.nodes([one, try flower(2)], scene: scene).first { $0.flower.id == one.id }!
            XCTAssertEqual(before.frame.midX, after.frame.midX)
            XCTAssertEqual(before.frame.midY, after.frame.midY)
        }
    }
    func testSparseFlowersAreReadableAndGrowOnlyInSceneFoliage() throws {
        for scene in MemoryScene.allCases {
            let nodes = MemoryFlowerLayout.nodes(try [flower(1), flower(2)], scene: scene)
            for node in nodes {
                XCTAssertGreaterThan(node.frame.width * 0.43, 40, "Sparse memories need recognizable petals.")
                let point = CGPoint(x: node.frame.midX / MemoryFlowerLayout.size.width,
                                    y: node.frame.midY / MemoryFlowerLayout.size.height)
                XCTAssertTrue(MemoryFlowerLayout.plantingRegions(for: scene).contains { $0.contains(point) })
            }
        }
    }
    func testAllCategoriesAreRetainedAndMappedWithoutRenaming() async throws {
        let store = MemoryGardenStore(api: GardenFake(try [flower(1, category: "旅行"), flower(2, category: "医疗")]))
        await store.load()
        XCTAssertTrue(store.categories.contains("医疗"))
        XCTAssertEqual(MemoryScene.forCategory("生活"), .castle)
        XCTAssertEqual(MemoryScene.forCategory("身体"), .courtyard)
        XCTAssertEqual(MemoryScene.forCategory("医疗"), .courtyard)
        XCTAssertEqual(store.visible(includeOthers: false, category: "旅行").count, 1)
    }
    func testLoveWitherReviveAndReloadUseServerState() async throws {
        let api = GardenFake(try [flower(1)])
        let store = MemoryGardenStore(api: api)
        await store.load()
        let loved = await store.change(store.flowers[0], action: "love")
        XCTAssertTrue(loved)
        XCTAssertTrue(store.flowers[0].loved)
        await store.change(store.flowers[0], action: "wither", note: "匿名更正")
        XCTAssertTrue(store.visible(includeOthers: true).isEmpty)
        await store.change(store.flowers[0], action: "revive")
        await store.load()
        XCTAssertEqual(store.visible(includeOthers: false).count, 1)
        let actions = await api.actions
        XCTAssertEqual(actions, ["love", "wither", "revive"])
    }
    func testFailedMutationAndLoadDoNotFabricateSuccessOrEmptyState() async throws {
        let api = GardenFake(try [flower(1)])
        let store = MemoryGardenStore(api: api)
        await store.load()
        await api.failing(true)
        let success = await store.change(store.flowers[0], action: "wither")
        XCTAssertFalse(success)
        await store.load()
        XCTAssertEqual(store.flowers[0].state, "bloom")
        XCTAssertNotNil(store.error)
        let empty = MemoryGardenStore(api: api)
        await empty.load()
        XCTAssertFalse(empty.loaded, "Network error is not an empty garden.")
    }
    func testLayout647Cost() throws {
        let rows = try (0..<647).map { try flower($0) }
        measure { _ = MemoryFlowerLayout.nodes(rows, scene: .water) }
    }
    func testClustersKeepEveryRealIDAndLabelsDoNotOverlap() throws {
        let rows = try (0..<647).map { try flower($0, state: $0 % 9 == 0 ? "fallen" : "bloom") }
        for scene in MemoryScene.allCases {
            let groups = MemoryFlowerLayout.clusters(MemoryFlowerLayout.nodes(rows, scene: scene))
            XCTAssertEqual(groups.flatMap(\.nodes).count, 647)
            XCTAssertEqual(Set(groups.flatMap(\.nodes).map { $0.flower.id }).count, 647)
            for i in groups.indices {
                XCTAssertLessThan(groups[i].bounds.maxY, 1630, "Keep flowers above the bottom controls.")
                for j in groups.indices where j > i { XCTAssertFalse(groups[i].bounds.intersects(groups[j].bounds)) }
            }
        }
    }
}

private actor QuotesFake: AppQuotesAPI {
    var quotes: [AppQuote] = []
    var failed = false
    var saves = 0
    func fail() { failed = true }
    func appQuotes() async throws -> AppQuotePage { AppQuotePage(quotes: quotes) }
    func saveAppQuote(messageID: Int, note: String) async throws {
        if failed { throw URLError(.notConnectedToInternet) }
        saves += 1
        quotes.append(AppQuote(id: messageID, message_id: messageID, text: "匿名原话", note: note, scene: "daily", created_at: "2026-10-12"))
    }
    func removeAppQuote(id: Int) async throws {
        if failed { throw URLError(.notConnectedToInternet) }
        quotes.removeAll { $0.id == id }
    }
}
@MainActor final class AppQuotesStoreTests: XCTestCase {
    func testOnlyCompletedServerKeMessageCanBeSaved() async {
        let api = QuotesFake()
        let store = AppQuotesStore(api: api)
        var message = Message(id: "test", serverID: 1, sender: .ke, text: "匿名原话", time: .now)
        message.isStreaming = true
        var result = await store.save(message: message, note: "")
        XCTAssertFalse(result)
        message.isStreaming = false
        message = Message(id: "test", serverID: 1, sender: .me, text: "匿名原话", time: .now)
        result = await store.save(message: message, note: "")
        XCTAssertFalse(result)
        message = Message(id: "test", serverID: 1, sender: .ke, text: "匿名原话", time: .now)
        message.serverID = nil
        result = await store.save(message: message, note: "")
        XCTAssertFalse(result)
        let saves = await api.saves
        XCTAssertEqual(saves, 0)
    }
    func testSaveBookmarkDeleteAndFailurePreservesQuote() async {
        let api = QuotesFake()
        let store = AppQuotesStore(api: api)
        let message = Message(id: "test", serverID: 7, sender: .ke, text: "匿名原话", time: .now)
        let tooLong = await store.save(message: message, note: String(repeating: "字", count: 1001))
        XCTAssertFalse(tooLong)
        let success = await store.save(message: message, note: "")
        XCTAssertTrue(success)
        XCTAssertNotNil(store.quote(messageID: 7))
        let removed = await store.remove(store.quotes[0])
        XCTAssertTrue(removed)
        XCTAssertNil(store.quote(messageID: 7))
        _ = await store.save(message: message, note: "备注")
        await api.fail()
        let failed = await store.remove(store.quotes[0])
        XCTAssertFalse(failed)
        XCTAssertEqual(store.quotes.count, 1)
    }
    func testBookmarkParticipatesInTimelineIdentity() {
        let message = Message(id: "test", serverID: 7, sender: .ke, text: "匿名原话", time: .now)
        let before = ChatTimelineItem.make(messages: [message], highlightedMessageID: nil, visibleSegmentCount: { _ in nil })
        let after = ChatTimelineItem.make(messages: [message], highlightedMessageID: nil, quotedIDs: [7], visibleSegmentCount: { _ in nil })
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after.first(where: { $0.kind == .message })?.isQuoted, true)
    }
}
