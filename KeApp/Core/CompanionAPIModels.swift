import Foundation

struct RemoteAnniversary: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let date: String
    let emoji: String?
    let days: Int?
}

struct RemoteSchedule: Decodable, Sendable {
    let current: [RemoteReminder]
    let history: [RemoteReminder]
}

struct RemoteReminder: Decodable, Identifiable, Sendable {
    let id: Int
    let text: String
    let scheduled_for: String
    let status: String
    let outcome: String
    let outcome_label: String
    let due: Bool
}

struct RemoteShift: Decodable, Identifiable, Sendable {
    let date: String
    let shift: String
    let note: String?
    var id: String { date }
}

struct RemotePeriod: Codable, Identifiable, Sendable {  // 126：Codable——本机留一份上次拉到的，重载时月历不闪
    let id: Int
    let start_date: String
    let end_date: String?
    let note: String?
}

struct RemoteIntimateCount: Decodable, Identifiable, Sendable {
    let date: String
    let count: Int
    var id: String { date }
}

struct RemoteDiary: Decodable, Identifiable, Sendable {
    let id: Int
    let title: String
    let content: String
    let author: String?
    let mood: String?
    let created_at: String
    let locked_hidden: Bool
    let comments: Int
    /// 「dream」是柯夜里的梦；没有或其它值都是日记。
    var kind: String? = nil
    /// 柯锁过这一页（1）；revealed=1 是锁过、后来给她打开了
    var locked: Int? = nil
    var revealed: Int? = nil
}

struct RemoteMoment: Decodable, Identifiable, Sendable {
    let id: Int
    let author: String
    let content: String
    let image: String?
    let created_at: String
    let user_liked: Int
    let ai_liked: Int
    let comments: [RemoteMomentComment]
}

struct RemoteMomentComment: Decodable, Identifiable, Sendable {
    let id: Int
    let author: String
    let content: String
    let created_at: String
}

enum CompanionDate {
    // 136：日历和格式器只建一次（以前每解一个日子都新建，「柯的」页每帧要解好几次）
    static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.firstWeekday = 2
        return value
    }()

    private static let formatters: [DateFormatter] = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        formatter.dateFormat = format
        return formatter
    }
    private static let iso = ISO8601DateFormatter()

    static func parse(_ value: String) -> Date? {
        for formatter in formatters {
            if let date = formatter.date(from: value), formatter.string(from: date) == value { return date }
        }
        return iso.date(from: value)
    }
}

struct RemotePrivateRecord: Decodable, Identifiable, Sendable {
    let id: Int
    let kind: String
    let date: String
    let note: String
}

struct ArchivedChatMessage: Decodable, Identifiable, Sendable {
    let id: Int
    let author: String
    let content: String
    let msg_type: String
    let created_at: String
}
