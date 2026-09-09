import Foundation

@MainActor
final class TimeDataStore: ObservableObject {
    @Published var anniversaries: [Anniversary] = []
    @Published var reminders: [TimeEntry] = []
    @Published var pending: [TimeEntry] = []
    @Published var shifts: [TimeEntry] = []
    @Published var periods: [TimeEntry] = []
    @Published var intimate: [TimeEntry] = []
    @Published var loading = false
    @Published var error: String?
    @Published var privateError: String?
    private let api: APIClient
    private var privateRequest = UUID()
    var entries: [TimeEntry] { reminders + shifts + periods + intimate }
    init(api: APIClient) { self.api = api }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        var failures: [String] = []
        do {
            anniversaries = try await api.fetchAnniversaries().map {
                guard let date = CompanionDate.parse($0.date) else { throw APIError.invalidResponse }
                return Anniversary(id: String($0.id), title: $0.name, date: date, isYearly: false)
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
            periods = try await api.fetchPeriods().map {
                guard let date = CompanionDate.parse($0.start_date) else { throw APIError.invalidResponse }
                return TimeEntry(id: "period:\($0.id)", date: date, title: ($0.note ?? "").isEmpty ? "生理期开始" : $0.note!, time: "全天", kind: .period)
            }
        } catch { failures.append("生理期") }
        error = failures.isEmpty ? nil : failures.joined(separator: "、") + "没有刷新成功，请重试。"
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
            guard let id = Int(rawID) else { throw APIError.invalidResponse }
            try await api.deletePeriod(id: id)
        case .intimate:
            guard let id = Int(rawID) else { throw APIError.invalidResponse }
            try await api.deletePrivateRecord(id: id, operationID: UUID().uuidString)
        case .reminder: return
        }
        await refresh()
    }
}
