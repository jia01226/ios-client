import XCTest
@testable import KeApp

/// 126：「我们」月历上的粉色经期不闪、今天点了「走了」那一行怎么说。
@MainActor
final class PeriodDisplayTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "PeriodDisplayTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func day(_ offset: Int, from store: PeriodStore) -> String {
        PeriodStore.dayKey(store.today, plus: offset) ?? store.today
    }

    // MARK: 5a 重载时不闪

    func testFailedReloadKeepsPreviousRecords() async {
        let api = DisplayPeriodFake()
        let store = PeriodStore(api: api, defaults: defaults)
        api.rows = [RemotePeriod(id: 1, start_date: day(-3, from: store), end_date: nil, note: nil)]
        await store.load()
        XCTAssertEqual(store.records.map(\.id), [1])
        api.fail = true
        await store.load()
        XCTAssertEqual(store.records.map(\.id), [1], "没接上就留着上一次的，月历不变白")
        XCTAssertNotNil(store.error)
    }

    func testRecordsStayVisibleWhileReloadIsInFlight() async {
        let api = DisplayPeriodFake()
        let store = PeriodStore(api: api, defaults: defaults)
        api.rows = [RemotePeriod(id: 1, start_date: day(-2, from: store), end_date: nil, note: nil)]
        await store.load()
        api.hold = true
        let reload = Task { await store.load() }
        // 让重载跑到「等服务器」那一步
        for _ in 0..<20 where !api.isWaiting { await Task.yield() }
        XCTAssertTrue(api.isWaiting)
        XCTAssertTrue(store.loading)
        XCTAssertEqual(store.records.map(\.id), [1], "拉着的时候不先清空")
        api.rows = [RemotePeriod(id: 1, start_date: day(-2, from: store), end_date: nil, note: nil),
                    RemotePeriod(id: 2, start_date: day(-40, from: store), end_date: day(-35, from: store), note: nil)]
        api.release()
        await reload.value
        XCTAssertEqual(Set(store.records.map(\.id)), [1, 2], "拉成功才换成新的")
    }

    func testNewStoreStartsWithLastRecordsBeforeItLoads() async {
        let api = DisplayPeriodFake()
        let first = PeriodStore(api: api, defaults: defaults)
        api.rows = [RemotePeriod(id: 7, start_date: day(-1, from: first), end_date: nil, note: nil)]
        await first.load()
        // 换页回来：「我们」页重新建一个 store，还没拉之前就有上次的经期可画
        api.fail = true
        let again = PeriodStore(api: api, defaults: defaults)
        XCTAssertEqual(again.records.map(\.id), [7])
        XCTAssertFalse(again.loaded)
        await again.load()
        XCTAssertEqual(again.records.map(\.id), [7])
    }

    func testDeletedRecordDoesNotComeBackFromCache() async {
        let api = DisplayPeriodFake()
        let store = PeriodStore(api: api, defaults: defaults)
        let row = RemotePeriod(id: 3, start_date: day(-20, from: store), end_date: day(-15, from: store), note: nil)
        api.rows = [row]
        await store.load()
        await store.delete(row)
        XCTAssertTrue(PeriodStore(api: api, defaults: defaults).records.isEmpty)
    }

    func testCacheIsPerLine() async {
        let api = DisplayPeriodFake()
        let one = PeriodStore(api: api, defaults: defaults, scope: "test1")
        api.rows = [RemotePeriod(id: 1, start_date: day(-1, from: one), end_date: nil, note: nil)]
        await one.load()
        XCTAssertTrue(PeriodStore(api: api, defaults: defaults, scope: "test2").records.isEmpty)
    }

    // MARK: 5b 今天走了

    func testEndedTodayAndConfirmedSaysToldKe() async {
        let api = DisplayPeriodFake()
        let store = PeriodStore(api: api, defaults: defaults)
        api.rows = [RemotePeriod(id: 1, start_date: day(-5, from: store), end_date: store.today, note: nil)]
        await store.load()
        XCTAssertEqual(store.summary, "今天走了 · 已告诉柯")
    }

    func testEndedTodayStillSendingSaysTelling() async {
        let api = DisplayPeriodFake()
        let store = PeriodStore(api: api, defaults: defaults)
        api.rows = [RemotePeriod(id: 1, start_date: day(-4, from: store), end_date: nil, note: nil)]
        await store.load()
        api.endWorks = false   // 服务器还没确认
        await store.finish()
        XCTAssertEqual(store.pendingEnds[1], store.today)
        XCTAssertEqual(store.summary, "今天走了 · 正在告诉柯")
        // 接通后确认了，就是「已告诉柯」
        api.endWorks = true
        await store.syncEnds()
        XCTAssertTrue(store.pendingEnds.isEmpty)
        XCTAssertEqual(store.summary, "今天走了 · 已告诉柯")
    }

    func testEarlierEndKeepsTheOldSummaries() async {
        let api = DisplayPeriodFake()
        let store = PeriodStore(api: api, defaults: defaults)
        let start = day(-30, from: store), end = day(-25, from: store)
        api.rows = [RemotePeriod(id: 1, start_date: start, end_date: end, note: nil)]
        await store.load()
        XCTAssertEqual(store.summary, "上次 \(start) — \(end)")
    }
}

@MainActor private final class DisplayPeriodFake: PeriodAPI {
    var rows: [RemotePeriod] = []
    var fail = false
    var hold = false
    var endWorks = true
    private(set) var isWaiting = false
    private var waiter: CheckedContinuation<Void, Never>?

    func release() { hold = false; waiter?.resume(); waiter = nil }

    func fetchPeriods() async throws -> [RemotePeriod] {
        if hold {
            isWaiting = true
            await withCheckedContinuation { waiter = $0 }
            isWaiting = false
        }
        if fail { throw URLError(.notConnectedToInternet) }
        return rows
    }
    func addPeriod(startDate: String, note: String) async throws {
        rows.append(RemotePeriod(id: (rows.map(\.id).max() ?? 0) + 1, start_date: startDate, end_date: nil, note: note))
    }
    func deletePeriod(id: Int) async throws { rows.removeAll { $0.id == id } }
    func endPeriod(id: Int, endDate: String) async throws {
        guard endWorks else { throw URLError(.timedOut) }
        if let index = rows.firstIndex(where: { $0.id == id }) {
            rows[index] = RemotePeriod(id: id, start_date: rows[index].start_date, end_date: endDate, note: rows[index].note)
        }
    }
}
