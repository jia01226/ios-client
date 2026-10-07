import Foundation

enum ShiftTiming {
    static func end(on date: Date, startMinutes: Int, durationMinutes: Int, calendar: Calendar = .current) -> Date? {
        guard (0..<1440).contains(startMinutes), (1...1440).contains(durationMinutes),
              let start = calendar.date(bySettingHour: startMinutes / 60, minute: startMinutes % 60, second: 0, of: date) else { return nil }
        return start.addingTimeInterval(Double(durationMinutes) * 60)
    }
}

enum HomeReminderGate {
    static func canDeliver(isHome: Bool, locationAt: Date, motionAt: Date?, speed: Double, now: Date) -> Bool {
        guard isHome, abs(locationAt.timeIntervalSince(now)) < 60,
              let motionAt, abs(motionAt.timeIntervalSince(now)) < 120 else { return false }
        return speed >= 0 && speed < 2
    }
}

/// Clock times are stored independently of a particular calendar day.
struct ShiftPeriod: Codable, Equatable {
    var startMinutes: Int
    var endMinutes: Int
    var fullDay = false
}

struct ShiftPlan: Codable, Equatable {
    var periods: [ShiftPeriod]
    static let example = ShiftPlan(periods: [ShiftPeriod(startMinutes: 480, endMinutes: 960)])

    static func preset(kind: String) -> ShiftPlan? {
        switch kind {
        case "normal": return ShiftPlan(periods: [ShiftPeriod(startMinutes: 510, endMinutes: 720), ShiftPeriod(startMinutes: 840, endMinutes: 1050)])
        case "early": return ShiftPlan(periods: [ShiftPeriod(startMinutes: 510, endMinutes: 885)])
        case "deputy": return ShiftPlan(periods: [ShiftPeriod(startMinutes: 885, endMinutes: 1260)])
        default: return nil
        }
    }

    var timeSummary: String {
        periods.map { String(format: "%02d:%02d-%02d:%02d", $0.startMinutes / 60, $0.startMinutes % 60, $0.endMinutes / 60, $0.endMinutes % 60) }.joined(separator: "、")
    }

    struct Resolved {
        let periods: [DateInterval]
        var end: Date { periods.last!.end }
        var workMinutes: Int { Int(periods.reduce(0) { $0 + $1.duration } / 60) }
        var breakMinutes: Int { Int(end.timeIntervalSince(periods.first!.start) / 60) - workMinutes }
    }

    func resolve(on date: Date, calendar: Calendar = .current) -> Resolved? {
        guard (1...2).contains(periods.count) else { return nil }
        var result: [DateInterval] = []
        for period in periods {
            guard (0..<1440).contains(period.startMinutes), (0..<1440).contains(period.endMinutes),
                  period.startMinutes != period.endMinutes || period.fullDay,
                  var start = calendar.date(bySettingHour: period.startMinutes / 60, minute: period.startMinutes % 60, second: 0, of: date) else { return nil }
            if let previous = result.last, start < previous.end {
                guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
                start = next
                guard start >= previous.end else { return nil }
            }
            guard var end = calendar.date(bySettingHour: period.endMinutes / 60, minute: period.endMinutes % 60, second: 0, of: start) else { return nil }
            if end <= start {
                guard let next = calendar.date(byAdding: .day, value: 1, to: end) else { return nil }
                end = next
            }
            result.append(DateInterval(start: start, end: end))
        }
        guard let first = result.first, let last = result.last,
              let limit = calendar.date(byAdding: .day, value: 1, to: first.start), last.end <= limit else { return nil }
        return Resolved(periods: result)
    }

    static func load(kind: String, defaults: UserDefaults = .standard) -> ShiftPlan? {
        if let data = defaults.data(forKey: "us.shift-plan.v2." + kind),
           let plan = try? JSONDecoder().decode(ShiftPlan.self, from: data) { return plan }
        let prefix = "us.shift-profile." + kind
        let start = defaults.integer(forKey: prefix + ".start")
        let duration = defaults.integer(forKey: prefix + ".minutes")
        guard (0..<1440).contains(start), (1...1440).contains(duration) else { return preset(kind: kind) }
        return ShiftPlan(periods: [ShiftPeriod(startMinutes: start, endMinutes: (start + duration) % 1440, fullDay: duration == 1440)])
    }
    func save(kind: String, defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: "us.shift-plan.v2." + kind)
    }
}
