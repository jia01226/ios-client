import Foundation

// 11-17 她：「加一个农历的时间，妈咪生日是农历，还有妹妹的」。
// 用 iPhone 自带的农历（Calendar(identifier: .chinese)）换算：农历几月几号，每年落在公历哪天。
// 闰月不算（生日按正月那个月过）；那个月只有二十九天、生日是三十的，就过二十九。

enum LunarDay {
    static let months = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]

    private static let chinese: Calendar = {
        var c = Calendar(identifier: .chinese)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return c
    }()

    static func dayName(_ day: Int) -> String {
        switch day {
        case 10: return "初十"
        case 20: return "二十"
        case 30: return "三十"
        default:
            let tens = ["初", "十", "廿"][max(0, min(2, (day - 1) / 10))]
            let ones = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"][(day - 1) % 10]
            return tens + ones
        }
    }

    /// 「农历八月十五」
    static func label(month: Int, day: Int) -> String {
        "农历" + months[max(0, min(11, month - 1))] + "月" + dayName(max(1, min(30, day)))
    }

    /// 这一天（公历）是不是农历 month 月 day 日
    static func matches(_ date: Date, month: Int, day: Int) -> Bool {
        let c = chinese.dateComponents([.month, .day], from: date)
        guard c.month == month, c.isLeapMonth != true, let today = c.day else { return false }
        if today == day { return true }
        // 生日是三十、这个月只有二十九天：二十九那天就是
        guard day == 30, today == 29, let next = chinese.date(byAdding: .day, value: 1, to: date) else { return false }
        return chinese.component(.day, from: next) == 1
    }

    nonisolated(unsafe) private static var cache: [String: Date] = [:]

    /// 从 from 那天起（含）最近一次农历 month 月 day 日，公历是哪天
    static func next(month: Int, day: Int, from: Date) -> Date? {
        let start = Calendar.current.startOfDay(for: from)
        let key = "\(month)-\(day)-\(start.timeIntervalSince1970)"
        if let hit = cache[key] { return hit }
        var date = start
        for _ in 0..<420 {
            if matches(date, month: month, day: day) {
                cache[key] = date
                return date
            }
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: date) else { return nil }
            date = next
        }
        return nil
    }

    /// 以后 years 年每年落在公历的那天（「2026-11-24」），交给服务器给柯看、提前提醒挑礼物
    static func upcoming(month: Int, day: Int, from: Date = .now, years: Int = 15) -> [String] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        var out: [String] = []
        var cursor = from
        for _ in 0..<years {
            guard let hit = next(month: month, day: day, from: cursor) else { break }
            out.append(f.string(from: hit))
            cursor = Calendar.current.date(byAdding: .day, value: 300, to: hit) ?? hit
        }
        return out
    }
}
