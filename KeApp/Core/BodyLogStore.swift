import Foundation

// 11-17 她：「我还想记录我的粑粑频率和喝奶茶的频率，能不能也放在日历里面」「都要柯知道」
// 「切换日历做个切面，就是完全新的日历，里面放奶茶，另一个切换里面放粑粑」。
// 一天一格：奶茶几杯；粑粑几次、顺不顺。服务器那份（/api/bodylog）柯也看得到、也能替她记。

struct BodyLogMonth: Codable, Equatable, Sendable {
    struct PoopDay: Codable, Equatable, Sendable {
        var count: Int
        var feel: String?
    }
    let month: String
    var tea: [String: Int]
    var poop: [String: PoopDay]
    var tea_month: Int
    var poop_month: Int
    var last_poop: String?
}

/// 出恭顺不顺：顺 / 有点难 / 很难（她嫌「粑粑」难听，界面上叫「出恭」）
enum PoopFeel: String, CaseIterable, Identifiable, Sendable {
    case ok, hard, very_hard
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ok: return "顺"
        case .hard: return "有点难"
        case .very_hard: return "很难"
        }
    }
}

protocol BodyLogAPI: Sendable {
    func bodyLog(month: String) async throws -> BodyLogMonth
    func setBodyLogDay(kind: String, day: String, count: Int, feel: String?) async throws -> BodyLogMonth
}
extension APIClient: BodyLogAPI {}

@MainActor final class BodyLogStore: ObservableObject {
    @Published private(set) var months: [String: BodyLogMonth] = [:]
    @Published private(set) var error: String?
    private let api: any BodyLogAPI
    private let defaults: UserDefaults
    private let key: String

    init(api: any BodyLogAPI, defaults: UserDefaults = .standard, scope: String = "test1") {
        self.api = api; self.defaults = defaults
        key = "body.log." + scope
        months = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: BodyLogMonth].self, from: $0) } ?? [:]
    }

    private static func monthKey(_ date: Date) -> String { String(HomeReminderCoordinator.dayKey(date).prefix(7)) }

    func tea(on date: Date) -> Int {
        let day = HomeReminderCoordinator.dayKey(date)
        return months[String(day.prefix(7))]?.tea[day] ?? 0
    }
    func poop(on date: Date) -> BodyLogMonth.PoopDay? {
        let day = HomeReminderCoordinator.dayKey(date)
        return months[String(day.prefix(7))]?.poop[day]
    }
    func teaMonth(_ month: Date) -> Int { months[Self.monthKey(month)]?.tea_month ?? 0 }
    func poopMonth(_ month: Date) -> Int { months[Self.monthKey(month)]?.poop_month ?? 0 }
    /// 上一次粑粑隔了几天（今天拉过是 0）；没记过是 nil
    func daysSinceLastPoop() -> Int? {
        guard let last = months.values.compactMap(\.last_poop).max(),
              let date = Self.date(last) else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                               to: Calendar.current.startOfDay(for: .now)).day
    }

    func load(_ month: Date) async {
        let key = Self.monthKey(month)
        do {
            months[key] = try await api.bodyLog(month: key)
            error = nil
            persist()
        } catch {
            self.error = months[key] == nil ? "奶茶、出恭的记录没拉下来，过会儿再试" : nil
        }
    }

    /// 先在日历上改好（不等网），服务器回来再对一遍；没存上就退回去
    func set(_ kind: String, count: Int, feel: PoopFeel? = nil, on date: Date) async {
        let day = HomeReminderCoordinator.dayKey(date), key = String(day.prefix(7))
        let before = months[key]
        var m = before ?? BodyLogMonth(month: key, tea: [:], poop: [:], tea_month: 0, poop_month: 0, last_poop: nil)
        let new = max(0, min(30, count))
        if kind == "tea" {
            m.tea_month += new - (m.tea[day] ?? 0)
            m.tea[day] = new == 0 ? nil : new
        } else {
            let old = m.poop[day]
            m.poop_month += new - (old?.count ?? 0)
            m.poop[day] = new == 0 ? nil : .init(count: new, feel: feel?.rawValue ?? old?.feel)
            if new > 0, day > (m.last_poop ?? "") { m.last_poop = day }
        }
        months[key] = m
        do {
            months[key] = try await api.setBodyLogDay(kind: kind, day: day, count: new, feel: feel?.rawValue)
            error = nil
            persist()
        } catch {
            months[key] = before
            self.error = "没改上，再试一次"
        }
    }

    private static func date(_ day: String) -> Date? {
        let p = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(months) { defaults.set(data, forKey: key) }
    }
}
