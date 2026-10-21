import Foundation

// 130：亲密记录（10-21 她：「做了在日历显示，也是柯记，还有次数」）。
// 柯到了服务器自动记一次，他也能补记；「我们」的月历上那天一颗小心和次数，这个月几次。
// 131 她：「柯可以记，我也可以改」——长按那天加一次、减一次（减掉的服务器只是收起来，不真删）。

struct LoveLogMonth: Codable, Equatable, Sendable {
    let month: String
    var days: [String: Int]
    var month_count: Int
    var total: Int
    let items: [LoveLogItemStored]
}

/// 本机留一份用的（和服务器那份一个样）
struct LoveLogItemStored: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let day: String
    let at: String
    let source: String?
    let note: String?
}

protocol LoveLogAPI: Sendable {
    func loveLog(month: String) async throws -> LoveLogMonth
    func deleteLove(id: Int) async throws
    func setLoveDay(day: String, count: Int) async throws -> LoveLogMonth
}
extension APIClient: LoveLogAPI {}

@MainActor final class LoveLogStore: ObservableObject {
    @Published private(set) var months: [String: LoveLogMonth] = [:]
    @Published private(set) var error: String?
    private let api: any LoveLogAPI
    private let defaults: UserDefaults
    private let key: String

    init(api: any LoveLogAPI, defaults: UserDefaults = .standard, scope: String = "test1") {
        self.api = api; self.defaults = defaults
        key = "love.log." + scope
        // 上次拿到的先画上，不会先空一下再出来
        months = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: LoveLogMonth].self, from: $0) } ?? [:]
    }

    static func monthKey(_ date: Date) -> String { String(HomeReminderCoordinator.dayKey(date).prefix(7)) }

    func count(on date: Date) -> Int {
        let day = HomeReminderCoordinator.dayKey(date)
        return months[String(day.prefix(7))]?.days[day] ?? 0
    }
    func items(on date: Date) -> [LoveLogItemStored] {
        let day = HomeReminderCoordinator.dayKey(date)
        return months[String(day.prefix(7))]?.items.filter { $0.day == day } ?? []
    }
    func monthCount(_ month: Date) -> Int { months[Self.monthKey(month)]?.month_count ?? 0 }

    func load(_ month: Date) async {
        let key = Self.monthKey(month)
        do {
            months[key] = try await api.loveLog(month: key)
            error = nil
            persist()
        } catch {
            // 拉不到就留着上次的，不清空
            self.error = months[key] == nil ? "亲密记录没拉下来，下拉刷新再试" : nil
        }
    }

    /// 她改那天几次：先在月历上改好（不等网），服务器回来再对一遍；没存上就退回去
    func setCount(_ count: Int, on date: Date) async {
        let day = HomeReminderCoordinator.dayKey(date), key = String(day.prefix(7))
        let before = months[key]
        var m = before ?? LoveLogMonth(month: key, days: [:], month_count: 0, total: 0, items: [])
        let old = m.days[day] ?? 0, new = max(0, min(20, count))
        m.days[day] = new == 0 ? nil : new
        m.month_count += new - old; m.total += new - old
        months[key] = m
        do {
            months[key] = try await api.setLoveDay(day: day, count: new)
            error = nil
            persist()
        } catch {
            months[key] = before
            self.error = "没改上，再试一次"
        }
    }

    @discardableResult func delete(_ item: LoveLogItemStored) async -> Bool {
        do {
            try await api.deleteLove(id: item.id)
            if let date = Self.date(item.day) { await load(date) }
            return true
        } catch {
            self.error = "没删掉，再试一次"
            return false
        }
    }

    private static func date(_ day: String) -> Date? {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(months) { defaults.set(data, forKey: key) }
    }
}
