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
