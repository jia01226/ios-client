import Foundation
import Combine

/// Dedicated notes contract. Never falls back to Moments (that route triggers feed replies).
struct StickyNote: Codable, Identifiable, Equatable, Sendable {
    enum Author: String, Codable { case user, ai }
    let id: String
    let author: Author
    let content: String
    let created_at: String
}

protocol StickyNotesAPI {
    func fetchStickyNotes() async throws -> [StickyNote]
}
extension APIClient: StickyNotesAPI {}

@MainActor
final class StickyNotesStore: ObservableObject {
    @Published private(set) var notes: [StickyNote] = []
    /// Retained for migration only. Old user drafts are never uploaded or shown as Ke's reminders.
    @Published private(set) var drafts: [StickyNote] = []
    @Published private(set) var archivedIDs: Set<String> = []
    @Published private(set) var loading = false
    @Published private(set) var status: String?
    private let api: any StickyNotesAPI
    private let defaults: UserDefaults
    private let key: String
    private var archiveObserver: AnyCancellable?
    private static let archiveChanged = Notification.Name("moonlight.notes.localArchiveChanged")
    static let archiveStatus = "收起状态暂存本机"

    /// Only Ke can leave reminders. Historical user notes remain in storage for a later migration.
    var all: [StickyNote] {
        reminders.filter { !archivedIDs.contains($0.id) }
    }
    var archived: [StickyNote] {
        reminders.filter { archivedIDs.contains($0.id) }
    }
    private var reminders: [StickyNote] {
        notes.filter { $0.author == .ai }.sorted { ($0.created_at, $0.id) > ($1.created_at, $1.id) }
    }
    init(api: any StickyNotesAPI, scope: String, defaults: UserDefaults = .standard) {
        self.api = api; self.defaults = defaults; key = "moonlight.notes.drafts." + scope
        notes = defaults.data(forKey: key + ".confirmed").flatMap { try? JSONDecoder().decode([StickyNote].self, from: $0) } ?? []
        drafts = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([StickyNote].self, from: $0) } ?? []
        refreshArchive()
        archiveObserver = NotificationCenter.default.publisher(for: Self.archiveChanged)
            .sink { [weak self] notification in
                guard let self, notification.object as? String == self.key else { return }
                self.refreshArchive()
            }
    }
    func load() async {
        refreshArchive()
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let fetched = try await api.fetchStickyNotes()
            notes = fetched; status = nil
            defaults.set(try? JSONEncoder().encode(notes), forKey: key + ".confirmed")
            // The server has no acknowledgement contract yet; fetching cannot clear local choices.
            refreshArchive()
        } catch { status = "暂时没有同步到新的提醒，已保存的便利贴仍留在这里。" }
    }

    func acknowledge(_ note: StickyNote) {
        guard note.author == .ai, notes.contains(where: { $0.id == note.id && $0.author == .ai }) else { return }
        refreshArchive()
        archivedIDs.insert(note.id)
        persistArchive()
    }

    func restore(_ note: StickyNote) {
        guard note.author == .ai else { return }
        refreshArchive()
        archivedIDs.remove(note.id)
        persistArchive()
    }

    private func refreshArchive() {
        archivedIDs = Set(defaults.stringArray(forKey: key + ".archived") ?? [])
    }
    private func persistArchive() {
        defaults.set(archivedIDs.sorted(), forKey: key + ".archived")
        NotificationCenter.default.post(name: Self.archiveChanged, object: key)
    }
}
