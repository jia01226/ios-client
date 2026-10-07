import XCTest
@testable import KeApp

@MainActor
final class ShiftSyncTests: XCTestCase {
    private let suite = "ShiftSyncTests." + UUID().uuidString
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    private var today: Date { Calendar.current.startOfDay(for: .now) }

    func testRequestedPresetsAndEditableTimes() throws {
        defer { defaults.removePersistentDomain(forName: suite) }
        let normal = try XCTUnwrap(ShiftPlan.load(kind: "normal", defaults: defaults))
        XCTAssertEqual(normal.timeSummary, "08:30-12:00、14:00-17:30")
        XCTAssertEqual(normal.resolve(on: today)?.workMinutes, 420)
        XCTAssertEqual(normal.resolve(on: today)?.breakMinutes, 120)
        for (kind, times) in [("early", "08:30-14:45"), ("deputy", "14:45-21:00")] {
            let plan = try XCTUnwrap(ShiftPlan.load(kind: kind, defaults: defaults))
            XCTAssertEqual(plan.timeSummary, times)
            XCTAssertEqual(plan.resolve(on: today)?.workMinutes, 375)
        }
        let custom = ShiftPlan(periods: [ShiftPeriod(startMinutes: 540, endMinutes: 960)])
        custom.save(kind: "normal", defaults: defaults)
        XCTAssertEqual(ShiftPlan.load(kind: "normal", defaults: defaults), custom)
        let note = ShiftNote.encode(plan: custom, note: "去分院", dayOverride: true)
        XCTAssertEqual(ShiftNote.plan(from: note), custom)
        XCTAssertEqual(ShiftNote.userNote(from: note), "去分院")
        XCTAssertNil(ShiftNote.plan(from: "上班时间：28:00-30:00"))
    }

    func testSaveAndCancelReachKeWithoutPostingExampleDays() async throws {
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = ShiftAPIFake()
        let vm = UsViewModel(defaults: defaults, shiftAPI: api)
        vm.setShift(.normal, on: today)
        await vm.syncShifts()
        let rows = await api.fetchShifts()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.shift, "正常班")
        XCTAssertTrue(rows.first?.note?.contains("08:30-12:00、14:00-17:30") == true)
        vm.setShift(nil, on: today)
        XCTAssertNil(vm.shift(on: today))
        XCTAssertNil(vm.shiftPlan(on: today))
        await vm.syncShifts()
        let after = await api.fetchShifts()
        XCTAssertTrue(after.isEmpty)
        await vm.refreshShifts()
        XCTAssertNil(vm.shift(on: today))
    }

    func testProfileUpdateKeepsDayOverrideAndPastShift() async throws {
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = ShiftAPIFake()
        let vm = UsViewModel(defaults: defaults, shiftAPI: api)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        for day in [yesterday, today, tomorrow] { vm.setShift(.normal, on: day) }
        await vm.syncShifts()
        let special = ShiftPlan(periods: [ShiftPeriod(startMinutes: 540, endMinutes: 900)])
        vm.saveShiftOverride(special, on: tomorrow)
        await vm.syncShifts()
        let custom = ShiftPlan(periods: [ShiftPeriod(startMinutes: 600, endMinutes: 960)])
        vm.saveShiftProfile(custom, kind: .normal)
        await vm.syncShifts()
        let rows = await api.fetchShifts()
        let byDate = Dictionary(uniqueKeysWithValues: rows.map { ($0.date, $0) })
        XCTAssertEqual(ShiftNote.plan(from: byDate[HomeReminderCoordinator.dayKey(today)]?.note ?? ""), custom)
        XCTAssertEqual(ShiftNote.plan(from: byDate[HomeReminderCoordinator.dayKey(tomorrow)]?.note ?? ""), special)
        XCTAssertEqual(ShiftNote.plan(from: byDate[HomeReminderCoordinator.dayKey(yesterday)]?.note ?? ""), ShiftPlan.preset(kind: "normal"))
        XCTAssertEqual(byDate[HomeReminderCoordinator.dayKey(today)]?.shift, "正常班（已调整）")
        XCTAssertEqual(vm.shiftPlan(on: tomorrow), special)
        XCTAssertEqual(vm.shiftPlan(on: yesterday), ShiftPlan.preset(kind: "normal"))
        await vm.refreshShifts()
        XCTAssertEqual(vm.shiftPlan(on: tomorrow), special)
        XCTAssertEqual(vm.shiftPlan(on: today), custom)
    }

    func testOfflineCancellationSurvivesRelaunchAndDoesNotGetRestoredByFetch() async {
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = ShiftAPIFake()
        let vm = UsViewModel(defaults: defaults, shiftAPI: api)
        vm.setShift(.early, on: today)
        await vm.syncShifts()
        await api.failWrites(true)
        vm.setShift(nil, on: today)
        await vm.syncShifts()
        XCTAssertTrue(vm.shiftSyncStatus?.contains("暂未同步") == true)
        let relaunched = UsViewModel(defaults: defaults, shiftAPI: api)
        await relaunched.refreshShifts()
        XCTAssertNil(relaunched.shift(on: today))
        await api.failWrites(false)
        await relaunched.syncShifts()
        let rows = await api.fetchShifts()
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(relaunched.shiftSyncStatus, "班表已同步，柯能看到")
    }

    func testCancelWhileSaveInFlightWins() async {
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = ShiftAPIFake()
        await api.holdNextWrite()
        let vm = UsViewModel(defaults: defaults, shiftAPI: api)
        vm.setShift(.deputy, on: today)
        await waitUntil { await api.writeIsHeld }
        vm.setShift(nil, on: today)
        await api.releaseWrite()
        await waitUntil { !vm.syncingShifts }
        let rows = await api.fetchShifts()
        XCTAssertTrue(rows.isEmpty)
        let operations = await api.operations
        XCTAssertEqual(operations, ["save", "delete"])
        XCTAssertNil(vm.shift(on: today))
    }

    func testLateReadCannotRestoreCanceledShift() async {
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = ShiftAPIFake()
        let vm = UsViewModel(defaults: defaults, shiftAPI: api)
        vm.setShift(.normal, on: today)
        await vm.syncShifts()
        await api.holdNextRead()
        let fetch = Task { await vm.refreshShifts() }
        await waitUntil { await api.readIsHeld }
        vm.setShift(nil, on: today)
        await vm.syncShifts()
        await api.releaseRead()
        await fetch.value
        XCTAssertNil(vm.shift(on: today))
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for controlled API request")
    }
}

private actor ShiftAPIFake: ShiftAPI {
    private var rows: [String: RemoteShift] = [:]
    private var shouldFail = false
    private var holdWrite = false
    private var holdRead = false
    private var writeContinuation: CheckedContinuation<Void, Never>?
    private var readContinuation: CheckedContinuation<Void, Never>?
    var operations: [String] = []
    var writeIsHeld: Bool { writeContinuation != nil }
    var readIsHeld: Bool { readContinuation != nil }
    func failWrites(_ fail: Bool) { shouldFail = fail }
    func holdNextWrite() { holdWrite = true }
    func holdNextRead() { holdRead = true }
    func releaseWrite() { writeContinuation?.resume(); writeContinuation = nil }
    func releaseRead() { readContinuation?.resume(); readContinuation = nil }
    func fetchShifts() async -> [RemoteShift] {
        let snapshot = rows.values.sorted { $0.date < $1.date }
        if holdRead { holdRead = false; await withCheckedContinuation { readContinuation = $0 } }
        return snapshot
    }
    func setShift(date: String, shift: String, note: String) async throws {
        if holdWrite { holdWrite = false; await withCheckedContinuation { writeContinuation = $0 } }
        if shouldFail { throw URLError(.notConnectedToInternet) }
        operations.append("save")
        rows[date] = RemoteShift(date: date, shift: shift, note: note)
    }
    func deleteShift(date: String) async throws {
        if shouldFail { throw URLError(.notConnectedToInternet) }
        operations.append("delete")
        rows.removeValue(forKey: date)
    }
}
