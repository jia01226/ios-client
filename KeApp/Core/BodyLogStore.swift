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
    // 11-17 奶茶本本：一杯一条、花费、热量、这周第几杯、她定的预算
    var tea_cups: [TeaCup]?
    var tea_spend: Double?
    var tea_kcal: Int?
    var tea_week: Int?
    var tea_budget: TeaBudget?
    // 11-17 出恭本本：一次一条
    var poop_logs: [PoopLog]?
    var poop_hard: Int?
    var poop_none: Int?
}

/// 出恭一次：时间、顺不顺、用时、蹲了没出来、形状（选填）、备注
struct PoopLog: Codable, Equatable, Identifiable, Sendable {
    var id: String = ""
    var day: String
    var time: String?
    var feel: String?
    var duration: String?
    var none: Bool?
    var shape: String?
    var note: String?
    var author: String?

    var isNone: Bool { none ?? false }
}

enum PoopDuration: String, CaseIterable, Identifiable, Sendable {
    case lt5, fiveTo10 = "5to10", gt10
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lt5: return "5 分钟内"
        case .fiveTo10: return "5–10 分钟"
        case .gt10: return "10 分钟以上"
        }
    }
}

/// 形状（选填）：从硬到稀七档，名字是我们自己起的
enum PoopShape: String, CaseIterable, Identifiable, Sendable {
    case pebble, lumpy, cracked, banana, soft, mushy, watery
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pebble: return "小石子"
        case .lumpy: return "疙瘩条"
        case .cracked: return "裂纹条"
        case .banana: return "香蕉"
        case .soft: return "软团"
        case .mushy: return "糊糊"
        case .watery: return "水水"
        }
    }
}

/// 一杯奶茶（她记的、或者柯听她说了记的）
struct TeaCup: Codable, Equatable, Identifiable, Sendable {
    var id: String = ""
    var day: String
    var brand: String?
    var drink: String?
    var sugar: String?
    var ice: String?
    var toppings: String?
    var note: String?
    var photo: String?
    var price: Double?
    var kcal: Int?
    var kcal_by: String?
    var rating: Int?
    var author: String?
    var at: String?

    /// 品牌第一个字，做成日历上的小圆章（不用各家的 logo）
    var badge: String { String((brand?.trimmingCharacters(in: .whitespaces).first).map { String($0) } ?? "茶") }
    var title: String {
        let t = [brand, drink].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        return t.isEmpty ? "一杯奶茶" : t
    }
    var options: String {
        [sugar, ice, toppings].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " / ")
    }
}

struct TeaBudget: Codable, Equatable, Sendable {
    var month_budget: Double?
    var week_cups: Int?
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
    func savePoop(_ log: PoopLog) async throws -> (PoopLog, BodyLogMonth)
    func deletePoop(id: String) async throws
    func saveTeaCup(_ cup: TeaCup) async throws -> (TeaCup, BodyLogMonth)
    func deleteTeaCup(id: String) async throws
    func setTeaBudget(monthBudget: Double?, weekCups: Int?) async throws -> BodyLogMonth
    func uploadAttachment(data: Data, fileName: String, mimeType: String) async throws -> ChatAttachment
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
    func teaCups(on date: Date) -> [TeaCup] {
        let day = HomeReminderCoordinator.dayKey(date)
        return (months[String(day.prefix(7))]?.tea_cups ?? []).filter { $0.day == day }
    }
    func teaSpend(_ month: Date) -> Double { months[Self.monthKey(month)]?.tea_spend ?? 0 }
    func teaKcal(_ month: Date) -> Int { months[Self.monthKey(month)]?.tea_kcal ?? 0 }
    /// 这周第几杯、预算（预算不分月，取最近拉到的那份）
    var teaWeek: Int { months[Self.monthKey(.now)]?.tea_week ?? 0 }
    var teaBudget: TeaBudget? { months[Self.monthKey(.now)]?.tea_budget ?? months.values.compactMap(\.tea_budget).first }
    /// 记过的品牌，最近的在前（记一杯时点一下就填上）
    var recentBrands: [String] {
        let cups = months.values.flatMap { $0.tea_cups ?? [] }.sorted { ($0.at ?? $0.day) > ($1.at ?? $1.day) }
        var seen = Set<String>(), out: [String] = []
        for b in cups.compactMap(\.brand) where !b.isEmpty && seen.insert(b).inserted { out.append(b) }
        return Array(out.prefix(8))
    }

    func poopLogs(on date: Date) -> [PoopLog] {
        let day = HomeReminderCoordinator.dayKey(date)
        return (months[String(day.prefix(7))]?.poop_logs ?? []).filter { $0.day == day }.sorted { ($0.time ?? "") < ($1.time ?? "") }
    }
    func poopHard(_ month: Date) -> Int { months[Self.monthKey(month)]?.poop_hard ?? 0 }
    func poopNone(_ month: Date) -> Int { months[Self.monthKey(month)]?.poop_none ?? 0 }

    @discardableResult func savePoop(_ log: PoopLog) async -> Bool {
        do {
            let (_, month) = try await api.savePoop(log)
            months[month.month] = month
            error = nil; persist()
            return true
        } catch {
            self.error = "这次没存上，再试一次"
            return false
        }
    }

    func deletePoop(_ log: PoopLog) async {
        do {
            try await api.deletePoop(id: log.id)
            if let date = Self.date(log.day) { await load(date) }
        } catch {
            self.error = "没删掉，再试一次"
        }
    }

    @discardableResult func saveCup(_ cup: TeaCup) async -> Bool {
        do {
            let (_, month) = try await api.saveTeaCup(cup)
            months[month.month] = month
            error = nil; persist()
            return true
        } catch {
            self.error = "这杯没存上，再试一次"
            return false
        }
    }

    func deleteCup(_ cup: TeaCup) async {
        do {
            try await api.deleteTeaCup(id: cup.id)
            if let date = Self.date(cup.day) { await load(date) }
        } catch {
            self.error = "没删掉，再试一次"
        }
    }

    func setBudget(monthBudget: Double?, weekCups: Int?) async {
        do {
            let month = try await api.setTeaBudget(monthBudget: monthBudget, weekCups: weekCups)
            months[month.month] = month
            error = nil; persist()
        } catch {
            self.error = "预算没存上，再试一次"
        }
    }

    func uploadPhoto(_ data: Data) async -> String? {
        try? await api.uploadAttachment(data: data, fileName: "奶茶-\(UUID().uuidString.prefix(8)).jpg", mimeType: "image/jpeg").url
    }
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
