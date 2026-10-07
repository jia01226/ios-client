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
