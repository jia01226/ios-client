import Foundation
import Combine

/// Dedicated notes contract. Never falls back to Moments (that route triggers feed replies).
struct StickyNote: Codable, Identifiable, Equatable, Sendable {
    enum Author: String, Codable { case user, ai }
    let id: String
    let author: Author
    let content: String
    let created_at: String
    var acked: Bool
    var acked_at: String?
    init(id: String, author: Author, content: String, created_at: String, acked: Bool = false, acked_at: String? = nil) {
        self.id = id; self.author = author; self.content = content; self.created_at = created_at
        self.acked = acked; self.acked_at = acked_at
    }
    enum CodingKeys: String, CodingKey { case id, author, content, created_at, acked, acked_at }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        author = try c.decode(Author.self, forKey: .author)
        content = try c.decode(String.self, forKey: .content)
        created_at = try c.decode(String.self, forKey: .created_at)
        acked = try c.decodeIfPresent(Bool.self, forKey: .acked) ?? false
        acked_at = try c.decodeIfPresent(String.self, forKey: .acked_at)
    }
}

protocol StickyNotesAPI {
    func fetchStickyNotes() async throws -> [StickyNote]
    func setStickyNoteAcknowledged(id: String, acknowledged: Bool) async throws
}
extension APIClient: StickyNotesAPI {}

@MainActor
final class StickyNotesStore: ObservableObject {
    @Published private(set) var notes: [StickyNote] = []
    /// Retained for migration only. Old user drafts are never uploaded or shown as Ke's reminders.
    @Published private(set) var drafts: [StickyNote] = []
    @Published private(set) var archivedIDs: Set<String> = []
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published private(set) var status: String?
    private let api: any StickyNotesAPI
    private let defaults: UserDefaults
    private let key: String
    private var archiveObserver: AnyCancellable?
    private static let archiveChanged = Notification.Name("moonlight.notes.localArchiveChanged")
    static let archiveStatus = "收起和放回会同步到服务器"
    // Serialize migration/mutations across the two independently mounted note views.
    private static var activeScopes = Set<String>()

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
                self.notes = self.defaults.data(forKey: self.key + ".confirmed")
                    .flatMap { try? JSONDecoder().decode([StickyNote].self, from: $0) } ?? self.notes
                self.refreshArchive()
            }
    }
    func load() async {
        refreshArchive()
        guard !loading, !saving, Self.activeScopes.insert(key).inserted else { return }
        loading = true
        defer { loading = false; Self.activeScopes.remove(key) }
        do {
            notes = try await api.fetchStickyNotes()
            status = nil
            var legacy = Set(defaults.stringArray(forKey: key + ".archived") ?? [])
            for index in notes.indices where notes[index].author == .ai && legacy.contains(notes[index].id) {
                do {
                    if !notes[index].acked {
                        try await api.setStickyNoteAcknowledged(id: notes[index].id, acknowledged: true)
                        notes[index].acked = true
                    }
                    legacy.remove(notes[index].id)
                    // Remove each legacy ID only after that individual acknowledgement succeeds.
                    if legacy.isEmpty { defaults.removeObject(forKey: key + ".archived") }
                    else { defaults.set(legacy.sorted(), forKey: key + ".archived") }
                } catch { status = "部分旧的收起记录还没同步，下次会继续。" }
            }
            persistArchive()
        } catch { status = "暂时没有同步到新的提醒，已保存的便利贴仍留在这里。" }
    }

    @discardableResult func acknowledge(_ note: StickyNote) async -> Bool {
        await setAcknowledged(note, true)
    }

    @discardableResult func restore(_ note: StickyNote) async -> Bool {
        await setAcknowledged(note, false)
    }

    private func setAcknowledged(_ note: StickyNote, _ value: Bool) async -> Bool {
        guard note.author == .ai, notes.contains(where: { $0.id == note.id && $0.author == .ai }),
              !loading, !saving, Self.activeScopes.insert(key).inserted else { return false }
        saving = true
        defer { saving = false; Self.activeScopes.remove(key) }
        do {
            try await api.setStickyNoteAcknowledged(id: note.id, acknowledged: value)
            if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index].acked = value }
            var legacy = Set(defaults.stringArray(forKey: key + ".archived") ?? [])
            legacy.remove(note.id)
            if legacy.isEmpty { defaults.removeObject(forKey: key + ".archived") }
            else { defaults.set(legacy.sorted(), forKey: key + ".archived") }
            status = nil
            persistArchive()
            return true
        } catch {
            status = value ? "没有收起成功，请重试。" : "没有放回成功，请重试。"
            return false
        }
    }

    private func refreshArchive() {
        archivedIDs = Set(notes.filter { $0.author == .ai && $0.acked }.map(\.id))
            .union(defaults.stringArray(forKey: key + ".archived") ?? [])
    }
    private func persistArchive() {
        defaults.set(try? JSONEncoder().encode(notes), forKey: key + ".confirmed")
        refreshArchive()
        NotificationCenter.default.post(name: Self.archiveChanged, object: key)
    }
}
