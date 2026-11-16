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

    /// 11-16：和服务器（柯也记在那儿）来回一趟，时间按北京时间、带时区，不走样
    func testRemoteEventRoundTrip() {
        let remote = RemoteCalendarEvent(CalendarEvent(title: "看医生 戚元丽", start: Date(timeIntervalSince1970: 1_795_827_600),
                                                       alerts: [1440, 60], note: "东川三楼 351", author: "ke"))
        XCTAssertEqual(remote.start, "2026-11-28T09:00:00+08:00")
        let back = remote.event
        XCTAssertEqual(back?.start, Date(timeIntervalSince1970: 1_795_827_600))
        XCTAssertEqual(back?.author, "ke")
        XCTAssertEqual(back?.note, "东川三楼 351")
    }

    /// 11-17：柯记的「要跟医生说的」从服务器下来能读到；App 往上送时不带（冲不掉柯刚记的）
    func testSymptomsComeDownButNotUp() throws {
        let json = #"{"id":"A","title":"看医生","start":"2026-11-20T16:00:00+08:00","alerts":[1440],"note":"广脑 李启荣","author":"ke","symptoms":[{"at":"11-17 03:53","text":"凌晨 3 点多醒了就睡不着"}]}"#
        let remote = try JSONDecoder().decode(RemoteCalendarEvent.self, from: Data(json.utf8))
        let event = try XCTUnwrap(remote.event)
        XCTAssertEqual(event.symptoms, ["11-17 03:53 凌晨 3 点多醒了就睡不着"])
        XCTAssertNil(RemoteCalendarEvent(event).symptoms)
        XCTAssertEqual(CalendarEventStore.withoutStamp("11-17 03:53 凌晨 3 点多醒了就睡不着"), "凌晨 3 点多醒了就睡不着")
    }
}
