import Foundation

enum TimeEventKind: String, CaseIterable, Identifiable {
    case reminder = "提醒", shift = "排班", period = "生理期", intimate = "亲密"
    var id: String { rawValue }
    var isPrivate: Bool { self == .intimate }
}

struct TimeEntry: Identifiable {
    let id: String
    let date: Date
    let title: String
    let time: String
    let kind: TimeEventKind
}

struct TimeCalendarModel {
    var calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "zh_CN")
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.firstWeekday = 2
        return value
    }()

    func monthStart(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }

    func monthDays(_ date: Date) -> [Date?] {
        let start = monthStart(date)
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let range = calendar.range(of: .day, in: .month, for: start)!
        let days: [Date?] = range.map { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
        let cells = Array<Date?>(repeating: nil, count: leading) + days
        return cells + Array<Date?>(repeating: nil, count: (7 - cells.count % 7) % 7)
    }

    func movingMonth(_ date: Date, by offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: monthStart(date))!
    }

    func entries(on date: Date, in entries: [TimeEntry], kind: TimeEventKind?) -> [TimeEntry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: date) && (kind == nil || $0.kind == kind) }
            .sorted { $0.time < $1.time }
    }

}
