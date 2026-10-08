import Foundation
import Combine

protocol PeriodAPI {
    func fetchPeriods() async throws -> [RemotePeriod]
    func addPeriod(startDate: String, note: String) async throws
    func deletePeriod(id: Int) async throws
    func endPeriod(id: Int, endDate: String) async throws
}
extension APIClient: PeriodAPI {}

/// Starts/deletions use the existing service. End dates are queued until the
/// server accepts the explicit end operation; never delete a start to mark an end.
@MainActor
final class PeriodStore: ObservableObject {
    @Published private(set) var records: [RemotePeriod] = []
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published private(set) var loaded = false
    @Published private(set) var error: String?
    @Published private(set) var status: String?
    @Published private(set) var pendingEnds: [Int: String] = [:]
    private let api: any PeriodAPI
    private let defaults: UserDefaults
    private let pendingKey: String
    private let startedKey: String
    private var revision = 0

    init(api: any PeriodAPI, defaults: UserDefaults = .standard, scope: String = "test1") {
        self.api = api; self.defaults = defaults
        pendingKey = "period.pending-ends." + scope
        startedKey = "period.started-day." + scope
        pendingEnds = defaults.data(forKey: pendingKey).flatMap { try? JSONDecoder().decode([Int: String].self, from: $0) } ?? [:]
    }
    var today: String { HomeReminderCoordinator.dayKey(.now) }
    var latest: RemotePeriod? { records.sorted { ($0.start_date, $0.id) > ($1.start_date, $1.id) }.first }
    /// 2026-10-08：没写结束日的那次，最多按 7 天算（9 月 13 号那次一直没点「走了」，
    /// 月历就从 9 月 13 号一路染到今天）。超过 14 天还没结束的，当作忘了记，不再挡「来了」。
    static let assumedDays = 7
    func shownEnd(of record: RemotePeriod) -> String {
        if let end = pendingEnds[record.id] ?? record.end_date { return end }
        let cap = Self.dayKey(record.start_date, plus: Self.assumedDays - 1) ?? today
        return min(cap, today)
    }
    /// 还在进行中的那次（14 天以内、没写结束日）。
    var ongoing: RemotePeriod? {
        guard let latest, latest.end_date == nil, pendingEnds[latest.id] == nil, latest.start_date <= today,
              let stale = Self.dayKey(latest.start_date, plus: 14), today <= stale else { return nil }
        return latest
    }
    static func dayKey(_ key: String, plus days: Int) -> String? {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: key), let e = f.calendar.date(byAdding: .day, value: days, to: d) else { return nil }
        return f.string(from: e)
    }
    // 上一次还没走，就不能再点「来了」（以前会另开一条，她误点一下就多出一次经期）。
    var canStart: Bool { loaded && !saving && !loading && ongoing == nil && !records.contains { $0.start_date == today } && defaults.string(forKey: startedKey) != today }
    var canEnd: Bool { loaded && !saving && !loading && ongoing != nil }
    var summary: String {
        guard loaded else { return error == nil ? "正在看经期记录…" : "经期记录暂未加载" }
        guard let latest else { return "来的那天，记一下就好。" }
        if let end = pendingEnds[latest.id] { return "\(end) 走了 · 已记本机，待同步给柯" }
        if let end = latest.end_date { return "上次 \(latest.start_date) — \(end)" }
        if ongoing == nil { return "上次 \(latest.start_date) 来的，没记哪天走" }
        return "\(latest.start_date) 来了"
    }
    func load(allowDuringSave: Bool = false) async {
        guard !loading, !saving || allowDuringSave else { return }
        loading = true; error = nil
        let expected = revision
        defer { loading = false }
        do {
            let rows = try await api.fetchPeriods()
            guard expected == revision else { return }
            records = rows; loaded = true
            // Only an explicit matching end date confirms delivery to the server.
            for row in rows where pendingEnds[row.id] == row.end_date && row.end_date != nil { pendingEnds.removeValue(forKey: row.id) }
            persistEnds()
        } catch { self.error = "经期记录暂时没接上，点这里重试。" }
    }
    func start() async {
        guard canStart else { return }
        saving = true; status = nil; revision += 1
        defer { saving = false }
        do {
            try await api.addPeriod(startDate: today, note: "")
            defaults.set(today, forKey: startedKey)
            status = "今天来了，已经记给柯。"
            await load(allowDuringSave: true)
        } catch { status = "还没记上，请再试一次。" }
    }
    func finish() async {
        guard canEnd, let current = ongoing else { return }
        pendingEnds[current.id] = today; persistEnds(); revision += 1
        await syncEnds()
    }
    func syncEnds() async {
        guard !saving, !pendingEnds.isEmpty else { return }
        saving = true
        defer { saving = false }
        for (id, date) in pendingEnds.sorted(by: { $0.key < $1.key }) {
            do {
                try await api.endPeriod(id: id, endDate: date)
                // A legacy or incompatible response must not claim success.
                let rows = try await api.fetchPeriods()
                guard rows.contains(where: { $0.id == id && $0.end_date == date }) else { throw APIError.invalidResponse }
                records = rows; pendingEnds.removeValue(forKey: id); persistEnds(); revision += 1
                status = "结束日期已同步给柯。"
            } catch {
                status = "结束日期已记在本机，服务器尚未确认；接通后可重试同步。"
                return
            }
        }
    }
    func delete(_ record: RemotePeriod) async {
        guard !saving else { return }
        saving = true; revision += 1
        defer { saving = false }
        do {
            try await api.deletePeriod(id: record.id)
            records.removeAll { $0.id == record.id }
            pendingEnds.removeValue(forKey: record.id); persistEnds()
            if record.start_date == defaults.string(forKey: startedKey) { defaults.removeObject(forKey: startedKey) }
            status = "这条记录已删除。"
        } catch { status = "这条记录还没删掉，请重试。" }
    }
    private func persistEnds() { defaults.set(try? JSONEncoder().encode(pendingEnds), forKey: pendingKey) }
}
