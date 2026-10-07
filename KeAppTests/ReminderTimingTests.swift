import XCTest
@testable import KeApp

final class ReminderTimingTests: XCTestCase {
    func testNightShiftAndD3CrossMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))!
        let end = try XCTUnwrap(ShiftTiming.end(on: day, startMinutes: 22 * 60 + 30, durationMinutes: 8 * 60, calendar: calendar))
        let result = calendar.dateComponents([.day, .hour, .minute], from: end)
        XCTAssertEqual(result.day, 7); XCTAssertEqual(result.hour, 6); XCTAssertEqual(result.minute, 30)
        XCTAssertEqual(calendar.component(.hour, from: end.addingTimeInterval(3600)), 7)
        XCTAssertNil(ShiftTiming.end(on: day, startMinutes: -1, durationMinutes: 480))
        XCTAssertNil(ShiftTiming.end(on: day, startMinutes: 480, durationMinutes: 0))
    }
    func testSplitShiftExcludesLunchAndUsesLastEnd() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))!
        let plan = ShiftPlan(periods: [ShiftPeriod(startMinutes: 480, endMinutes: 720), ShiftPeriod(startMinutes: 780, endMinutes: 1020)])
        let shift = try XCTUnwrap(plan.resolve(on: day, calendar: calendar))
        XCTAssertEqual(shift.workMinutes, 480); XCTAssertEqual(shift.breakMinutes, 60)
        XCTAssertEqual(calendar.component(.hour, from: shift.end), 17)
        XCTAssertEqual(calendar.component(.hour, from: shift.end.addingTimeInterval(3600)), 18)
        let continuous = try XCTUnwrap(ShiftPlan.example.resolve(on: day, calendar: calendar))
        XCTAssertEqual(continuous.workMinutes, 480); XCTAssertEqual(continuous.breakMinutes, 0)
    }
    func testSplitNightShiftAndOverlapValidation() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))!
        let night = ShiftPlan(periods: [ShiftPeriod(startMinutes: 1320, endMinutes: 120), ShiftPeriod(startMinutes: 180, endMinutes: 360)])
        let shift = try XCTUnwrap(night.resolve(on: day, calendar: calendar))
        XCTAssertEqual(shift.workMinutes, 420); XCTAssertEqual(shift.breakMinutes, 60)
        XCTAssertEqual(calendar.component(.day, from: shift.end), 7)
        XCTAssertEqual(calendar.component(.hour, from: shift.end), 6)
        XCTAssertNil(ShiftPlan(periods: [ShiftPeriod(startMinutes: 480, endMinutes: 720), ShiftPeriod(startMinutes: 660, endMinutes: 1020)]).resolve(on: day, calendar: calendar))
        XCTAssertNil(ShiftPlan(periods: [ShiftPeriod(startMinutes: 1320, endMinutes: 120), ShiftPeriod(startMinutes: 60, endMinutes: 300)]).resolve(on: day, calendar: calendar))
        XCTAssertNil(ShiftPlan(periods: [ShiftPeriod(startMinutes: 480, endMinutes: 480)]).resolve(on: day, calendar: calendar))
    }
    func testOldProfileMigrationAndSplitPersistence() throws {
        let suite = "split-shift-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1320, forKey: "us.shift-profile.early.start"); defaults.set(480, forKey: "us.shift-profile.early.minutes")
        let old = try XCTUnwrap(ShiftPlan.load(kind: "early", defaults: defaults))
        XCTAssertEqual(old.periods, [ShiftPeriod(startMinutes: 1320, endMinutes: 360)])
        let split = ShiftPlan(periods: [ShiftPeriod(startMinutes: 480, endMinutes: 720), ShiftPeriod(startMinutes: 780, endMinutes: 1020)])
        split.save(kind: "early", defaults: defaults)
        XCTAssertEqual(ShiftPlan.load(kind: "early", defaults: defaults), split)
        XCTAssertNil(ShiftPlan.load(kind: "deputy", defaults: defaults))
    }
    func testHomeGateRejectsDrivingUnknownAndStaleSignals() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(HomeReminderGate.canDeliver(isHome: true, locationAt: now, motionAt: now, speed: 0, now: now))
        XCTAssertFalse(HomeReminderGate.canDeliver(isHome: false, locationAt: now, motionAt: now, speed: 0, now: now))
        XCTAssertFalse(HomeReminderGate.canDeliver(isHome: true, locationAt: now, motionAt: nil, speed: 0, now: now))
        XCTAssertFalse(HomeReminderGate.canDeliver(isHome: true, locationAt: now, motionAt: now, speed: 12, now: now))
        XCTAssertFalse(HomeReminderGate.canDeliver(isHome: true, locationAt: now, motionAt: now, speed: -1, now: now))
        XCTAssertFalse(HomeReminderGate.canDeliver(isHome: true, locationAt: now.addingTimeInterval(-61), motionAt: now, speed: 0, now: now))
        XCTAssertFalse(HomeReminderGate.canDeliver(isHome: true, locationAt: now, motionAt: now.addingTimeInterval(-121), speed: 0, now: now))
    }
}
