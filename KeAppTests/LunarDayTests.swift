import XCTest
@testable import KeApp

/// 11-17：妈咪、妹妹的生日按农历过——农历几月几号落在公历哪天、日历上那格认不认得出
final class LunarDayTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testNamesReadLikeTheLunarCalendar() {
        XCTAssertEqual(LunarDay.label(month: 8, day: 15), "农历八月十五")
        XCTAssertEqual(LunarDay.label(month: 11, day: 1), "农历冬月初一")
        XCTAssertEqual(LunarDay.label(month: 12, day: 23), "农历腊月廿三")
        XCTAssertEqual(LunarDay.dayName(10), "初十")
        XCTAssertEqual(LunarDay.dayName(30), "三十")
    }

    func testNextFindsTheSolarDay() {
        // 2026 年中秋（农历八月十五）是 9 月 25 日；2027 年春节（正月初一）是 2 月 6 日
        XCTAssertEqual(LunarDay.next(month: 8, day: 15, from: day(2026, 1, 1)), day(2026, 9, 25))
        XCTAssertEqual(LunarDay.next(month: 1, day: 1, from: day(2026, 3, 1)), day(2027, 2, 6))
        XCTAssertTrue(LunarDay.matches(day(2026, 9, 25), month: 8, day: 15))
        XCTAssertFalse(LunarDay.matches(day(2026, 9, 26), month: 8, day: 15))
    }

    func testUpcomingGivesOneDayPerYear() {
        let solar = LunarDay.upcoming(month: 8, day: 15, from: day(2026, 1, 1), years: 3)
        XCTAssertEqual(solar.first, "2026-09-25")
        XCTAssertEqual(solar.count, 3)
        XCTAssertEqual(Set(solar.map { $0.prefix(4) }).count, 3)
    }
}
