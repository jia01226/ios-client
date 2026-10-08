import Foundation
import Combine

struct KeDiaryPage: Identifiable, Equatable {
    let date: Date
    let title: String
    let content: String
    var id: Date { date }
    static func dateLabel(_ date: Date, format: String = "yyyy年M月d日") -> String {
        let f = DateFormatter(); f.calendar = CompanionDate.calendar; f.timeZone = CompanionDate.calendar.timeZone
        f.locale = Locale(identifier: "zh_CN"); f.dateFormat = format
        return f.string(from: date)
    }
    static func collect(_ entries: [RemoteDiary]) -> [KeDiaryPage] {
        let visible = entries.filter {
            !$0.locked_hidden && ["柯", "ai", "assistant", "ke"].contains($0.author ?? "柯")
        }
        let dated = visible.compactMap { entry -> (Date, RemoteDiary)? in
            guard let date = CompanionDate.parse(entry.created_at) else { return nil }
            return (CompanionDate.calendar.startOfDay(for: date), entry)
        }
        return Dictionary(grouping: dated, by: { $0.0 }).map { date, rows in
            let entries = rows.map(\.1).sorted { ($0.created_at, $0.id) < ($1.created_at, $1.id) }
            return KeDiaryPage(date: date, title: entries.first?.title ?? "",
                               content: entries.map { $0.content }.joined(separator: "\n\n"))
        }.sorted { $0.date < $1.date }
    }
}

protocol KeDiaryAPI { func fetchDiaries(query: String, offset: Int, limit: Int) async throws -> [RemoteDiary] }
extension APIClient: KeDiaryAPI {}

@MainActor
final class KeDiaryStore: ObservableObject {
    @Published private(set) var pages: [KeDiaryPage] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var loaded = false
    @Published private(set) var historyIsComplete = false
    private let api: any KeDiaryAPI
    init(api: any KeDiaryAPI) { self.api = api }
    func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            var all: [RemoteDiary] = []; var seen = Set<Int>(); var offset = 0
            var complete = false
            while true {
                try Task.checkCancellation()
                let rows = try await api.fetchDiaries(query: "", offset: offset, limit: 50)
                let new = rows.filter { seen.insert($0.id).inserted }
                all.append(contentsOf: new)
                // Legacy API returns all rows without honoring pagination. Stop on repeated IDs.
                if rows.count < 50 { complete = true; break }
                if new.isEmpty { break }
                offset += rows.count
            }
            pages = KeDiaryPage.collect(all); loaded = true; historyIsComplete = complete
            if !complete { error = "已读到现有日记；更早的记录还需要接通。" }
        } catch is CancellationError {
        } catch { self.error = "日记暂时没接上，点这里再试一次。" }
    }
    func page(on date: Date) -> KeDiaryPage? {
        pages.first { CompanionDate.calendar.isDate($0.date, inSameDayAs: date) }
    }
}
