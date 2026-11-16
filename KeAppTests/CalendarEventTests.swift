import XCTest
@testable import KeApp

/// 1116：日历里她自己记的日程（看医生的号）：按天取、存下来再打开还在、删了就没了
@MainActor
final class CalendarEventTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "calendar-event-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testEventsAreGroupedByDayAndSortedByTime() {
        let store = CalendarEventStore(defaults: freshDefaults())
        let day = Calendar.current.date(from: DateComponents(year: 2030, month: 3, day: 5, hour: 0))!
        let later = Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: day)!
        let earlier = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        store.save(CalendarEvent(title: "复诊", start: later))
        store.save(CalendarEvent(title: "抽血", start: earlier))
        store.save(CalendarEvent(title: "别的天", start: day.addingTimeInterval(86_400 * 2)))

        XCTAssertEqual(store.events(on: day).map(\.title), ["抽血", "复诊"])
        XCTAssertTrue(store.hasEvents(on: day))
        XCTAssertFalse(store.hasEvents(on: day.addingTimeInterval(86_400)))
    }

    func testEventsPersistAndDelete() {
        let defaults = freshDefaults()
        let start = Calendar.current.date(from: DateComponents(year: 2030, month: 3, day: 5, hour: 9, minute: 30))!
        let event = CalendarEvent(title: "佛三院 李医生", start: start, alerts: [1440, 120], note: "带病历")
        CalendarEventStore(defaults: defaults).save(event)

        let reopened = CalendarEventStore(defaults: defaults)
        XCTAssertEqual(reopened.events, [event])

        reopened.delete(event.id)
        XCTAssertTrue(CalendarEventStore(defaults: defaults).events.isEmpty)
    }

    func testAlertLineReadsLikeTheCalendarApp() {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        XCTAssertEqual(DayEventsSection.alertLine(CalendarEvent(title: "a", start: start, alerts: [])), "不提醒")
        XCTAssertEqual(DayEventsSection.alertLine(CalendarEvent(title: "a", start: start, alerts: [1440, 120])),
                       "提醒：1 天前、2 小时前")
        XCTAssertEqual(DayEventsSection.alertLine(CalendarEvent(title: "a", start: start, alerts: [0])),
                       "提醒：日程开始时")
    }
}
