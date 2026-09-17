import Foundation

@MainActor
final class TimeDataStore: ObservableObject {
    @Published var anniversaries: [Anniversary] = []
    @Published var reminders: [TimeEntry] = []
    @Published var pending: [TimeEntry] = []
    @Published var shifts: [TimeEntry] = []
    @Published var periods: [TimeEntry] = []
    @Published var intimate: [TimeEntry] = []
    @Published var intimateCounts: [TimeEntry] = []
    @Published var loading = false
    @Published var error: String?
    @Published var privateError: String?
    private let api: APIClient
    private var privateRequest = UUID()
    private var countRequest = UUID()
    var entries: [TimeEntry] { reminders + shifts + periods + intimateCounts }
    init(api: APIClient) { self.api = api }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        var failures: [String] = []
        do {
            anniversaries = try await api.fetchAnniversaries().map {
                guard let date = CompanionDate.parse($0.date) else { throw APIError.invalidResponse }
                return Anniversary(id: String($0.id), title: $0.name, date: date, isYearly: true)
            }
        } catch { failures.append("纪念日") }
        do {
            let response = try await api.fetchSchedule()
            func entry(_ row: RemoteReminder) throws -> TimeEntry {
                guard let date = CompanionDate.parse(row.scheduled_for) else { throw APIError.invalidResponse }
                let suffix = row.outcome_label.isEmpty ? "" : " · " + row.outcome_label
                return TimeEntry(id: "reminder:\(row.id)", date: date, title: row.text + suffix,
                    time: String(row.scheduled_for.dropFirst(11).prefix(5)), kind: .reminder)
            }
            let all = try (response.current + response.history).map(entry)
            let current = try response.current.filter { $0.status == "pending" }.map(entry)
            reminders = all; pending = current.sorted { $0.date < $1.date }
        } catch { failures.append("提醒") }
        do {
            shifts = try await api.fetchShifts().map {
                guard let date = CompanionDate.parse($0.date) else { throw APIError.invalidResponse }
                return TimeEntry(id: "shift:\($0.date)", date: date, title: $0.shift + (($0.note ?? "").isEmpty ? "" : " · " + $0.note!), time: "全天", kind: .shift)
            }
        } catch { failures.append("排班") }
        do {
            periods = try await api.fetchPeriods().flatMap { item -> [TimeEntry] in
                guard let start = CompanionDate.parse(item.start_date) else { throw APIError.invalidResponse }
                let end = item.end_date.flatMap(CompanionDate.parse) ?? start
                guard end >= start else { throw APIError.invalidResponse }
                let count = min(14, CompanionDate.calendar.dateComponents([.day], from: start, to: end).day ?? 0)
                return (0...count).compactMap { offset in
                    CompanionDate.calendar.date(byAdding: .day, value: offset, to: start).map {
                        TimeEntry(id: "period:\(item.id):\(offset)", date: $0,
                            title: "月经期", time: "全天", kind: .period)
                    }
                }
            }
        } catch { failures.append("生理期") }
        error = failures.isEmpty ? nil : failures.joined(separator: "、") + "没有刷新成功，请重试。"
    }

    func loadIntimateCounts(start: String, end: String) async {
        let request = UUID()
        countRequest = request
        do {
            let values: [TimeEntry] = try await api.fetchIntimateCounts(start: start, end: end).compactMap {
                guard let date = CompanionDate.parse($0.date) else { return nil }
                return TimeEntry(id: "intimate-count:\($0.date)", date: date,
                    title: "亲密 \($0.count) 次", time: "全天", kind: .intimate)
            }
            guard countRequest == request else { return }
            intimateCounts = values
        } catch {
            guard countRequest == request else { return }
            privateError = "亲密次数没有刷新成功，请重试。"
        }
    }

    func hidePrivate() {
        privateRequest = UUID(); intimate = []; privateError = nil
    }

    func loadPrivate(date: String) async {
        let request = UUID(); privateRequest = request
        intimate = []; privateError = nil
        do {
            let records = try await api.fetchPrivateRecords(date: date)
            guard privateRequest == request else { return }
            intimate = try records.map {
                guard let date = CompanionDate.parse($0.date) else { throw APIError.invalidResponse }
                return TimeEntry(id: "intimate:\($0.id)", date: date, title: $0.note.isEmpty ? "亲密记录" : $0.note, time: "全天", kind: .intimate)
            }
        } catch {
            guard privateRequest == request else { return }
            privateError = "记录没有加载成功，请重试。"
        }
    }

    func remove(_ entry: TimeEntry) async throws {
        let rawID = String(entry.id.split(separator: ":", maxSplits: 1).last ?? "")
        switch entry.kind {
        case .shift: try await api.deleteShift(date: rawID)
        case .period:
            guard let id = Int(rawID.split(separator: ":").first ?? "") else { throw APIError.invalidResponse }
            try await api.deletePeriod(id: id)
        case .intimate:
            guard let id = Int(rawID) else { throw APIError.invalidResponse }
            try await api.deletePrivateRecord(id: id, operationID: UUID().uuidString)
        case .reminder: return
        }
        await refresh()
    }
}
