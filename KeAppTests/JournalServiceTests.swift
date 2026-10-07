import XCTest
@testable import KeApp

private let hutFixture = #"{"open_items":[{"id":"open-a","text":"还有下文","since":"2026-10-01"}],"recently_closed":[{"id":2,"text":"已经了结","closed_at":"2026-10-02","note":"记着"}],"cairn":[{"text":"想起的话","date":"2026-10-01","now":"现在很好"}],"polaroids":[],"fact_book":[{"category":"日常","count":1,"items":[{"text":"一个事实","date":"2026-10-01"}]}],"floe":null,"photos":[{"caption":"照片里的云","said":"很轻","date":"2026-10-01"}],"weather":{"facts":1,"lines":1,"photos":1,"open_items":1,"recalled_this_week":1,"summary":"晴"},"letters":[{"id":1,"text":"小纸条","created_at":"2026-10-01","status":"answered","reply":"我看到了","replied_at":"2026-10-02"}]}"#

@MainActor
final class JournalServiceTests: XCTestCase {
    func testHutContractHandlesBothIDTypesAndOptionalMemoryFields() throws {
        let hut = try JSONDecoder().decode(RemoteHut.self, from: Data(hutFixture.utf8))
        XCTAssertEqual(hut.open_items.first?.id.value, "open-a")
        XCTAssertEqual(hut.recently_closed.first?.id.value, "2")
        XCTAssertEqual(hut.cairn.first?.now, "现在很好")
        XCTAssertNil(hut.floe)
        XCTAssertEqual(hut.letters.first?.reply, "我看到了")
        XCTAssertEqual(hut.fact_book.first?.items.first?.text, "一个事实")
    }

    func testFailedLetterIsRetryableAndSuccessfulPostSurvivesRefreshFailure() async {
        let api = HutFake()
        let model = HutViewModel(api: api)
        await model.load()
        XCTAssertNotNil(model.hut)
        api.failWrite = true
        let failed = await model.send("还没发出的信")
        XCTAssertFalse(failed)
        XCTAssertNotNil(model.letterError)
        XCTAssertFalse(model.letterSent)
        api.failWrite = false; api.failRead = true
        let sent = await model.send("  已经发出的信  ")
        XCTAssertTrue(sent)
        XCTAssertTrue(model.letterSent)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(api.sent, ["已经发出的信"])
        let empty = await model.send("  ")
        XCTAssertFalse(empty)
        XCTAssertEqual(api.sent.count, 1)
    }

    func testPeriodEndDoesNotDeleteStartAndPersistsUntilServerConfirms() async throws {
        let suite = "PeriodTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = PeriodFake()
        let store = PeriodStore(api: api, defaults: defaults)
        await store.load()
        await store.start()
        XCTAssertEqual(api.addCount, 1)
        await store.start()
        XCTAssertEqual(api.addCount, 1)
        await store.finish()
        XCTAssertEqual(api.deleteCount, 0)
        XCTAssertEqual(store.pendingEnds.count, 1)
        XCTAssertEqual(store.records.count, 1)
        let restored = PeriodStore(api: api, defaults: defaults)
        await restored.load()
        XCTAssertEqual(restored.pendingEnds.count, 1)
        api.endMode = .falseReceipt
        await restored.syncEnds()
        XCTAssertEqual(restored.pendingEnds.count, 1, "An OK receipt without stored end_date is not success")
        api.endMode = .working
        await restored.syncEnds()
        XCTAssertTrue(restored.pendingEnds.isEmpty)
        XCTAssertEqual(restored.latest?.end_date, restored.today)
        let row = try XCTUnwrap(restored.latest)
        await restored.delete(row)
        XCTAssertEqual(api.deleteCount, 1)
        XCTAssertTrue(restored.records.isEmpty)
        XCTAssertTrue(restored.canStart)
    }

    func testFailedPeriodStartIsNotMarkedAsSynced() async {
        let suite = "PeriodTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = PeriodFake(); api.failStart = true
        let store = PeriodStore(api: api, defaults: defaults)
        await store.load(); await store.start()
        XCTAssertTrue(store.canStart)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(store.status?.contains("还没记上") == true)
    }
}

@MainActor private final class HutFake: HutAPI {
    var failWrite = false, failRead = false
    var sent: [String] = []
    func fetchHut() async throws -> RemoteHut {
        if failRead { throw URLError(.notConnectedToInternet) }
        return try JSONDecoder().decode(RemoteHut.self, from: Data(hutFixture.utf8))
    }
    func sendHutLetter(text: String) async throws {
        if failWrite { throw URLError(.notConnectedToInternet) }
        sent.append(text)
    }
}

@MainActor private final class PeriodFake: PeriodAPI {
    enum EndMode { case missing, falseReceipt, working }
    var rows: [RemotePeriod] = [], addCount = 0, deleteCount = 0
    var failStart = false
    var endMode = EndMode.missing
    func fetchPeriods() async throws -> [RemotePeriod] { rows }
    func addPeriod(startDate: String, note: String) async throws {
        if failStart { throw URLError(.notConnectedToInternet) }
        addCount += 1
        rows.append(RemotePeriod(id: addCount, start_date: startDate, end_date: nil, note: note))
    }
    func deletePeriod(id: Int) async throws { deleteCount += 1; rows.removeAll { $0.id == id } }
    func endPeriod(id: Int, endDate: String) async throws {
        if endMode == .missing { throw URLError(.badServerResponse) }
        if endMode == .working, let index = rows.firstIndex(where: { $0.id == id }) {
            rows[index] = RemotePeriod(id: id, start_date: rows[index].start_date, end_date: endDate, note: rows[index].note)
        }
    }
}
