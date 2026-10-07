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
    func saveStickyNote(id: String, content: String) async throws -> StickyNote
    func deleteStickyNote(id: String) async throws
}
extension APIClient: StickyNotesAPI {}

@MainActor
final class StickyNotesStore: ObservableObject {
    @Published private(set) var notes: [StickyNote] = []
    @Published private(set) var drafts: [StickyNote] = []
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published private(set) var status: String?
    private let api: any StickyNotesAPI
    private let defaults: UserDefaults
    private let key: String
    private var generation = 0
    var all: [StickyNote] {
        let draftIDs = Set(drafts.map(\.id))
        return (drafts + notes.filter { !draftIDs.contains($0.id) }).sorted { ($0.created_at, $0.id) > ($1.created_at, $1.id) }
    }
    init(api: any StickyNotesAPI, scope: String, defaults: UserDefaults = .standard) {
        self.api = api; self.defaults = defaults; key = "moonlight.notes.drafts." + scope
        drafts = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([StickyNote].self, from: $0) } ?? []
    }
    func isLocal(_ note: StickyNote) -> Bool { drafts.contains { $0.id == note.id } }
    func load() async {
        guard !loading, !saving else { return }
        loading = true
        let revision = generation
        defer { loading = false }
        do {
            let fetched = try await api.fetchStickyNotes()
            guard revision == generation else { return }
            notes = fetched; status = nil
            // Only a matching ID AND content confirms a previously timed-out write.
            drafts.removeAll { draft in fetched.contains { $0.id == draft.id && $0.content == draft.content && $0.author == .user } }
            persist()
        } catch { status = "同步暂未接通，新写的便利贴会先留在这台手机里。" }
    }
    func save(_ content: String, editing: StickyNote? = nil) async {
        guard !saving, editing == nil || editing?.author == .user else { return }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        generation += 1
        let note = StickyNote(id: editing?.id ?? UUID().uuidString, author: .user, content: text,
                              created_at: editing?.created_at ?? ISO8601DateFormatter().string(from: .now))
        drafts.removeAll { $0.id == note.id }; drafts.append(note); persist()
        saving = true; defer { saving = false }
        do {
            let saved = try await api.saveStickyNote(id: note.id, content: note.content)
            guard saved.id == note.id, saved.content == note.content, saved.author == .user else { throw APIError.invalidResponse }
            notes.removeAll { $0.id == saved.id }; notes.append(saved)
            drafts.removeAll { $0.id == saved.id }; persist(); status = nil
        } catch { status = "已保存在本机，尚未同步给柯。稍后可点这张便利贴重试。" }
    }
    func delete(_ note: StickyNote) async {
        guard note.author == .user, !saving else { return }
        saving = true; generation += 1
        defer { saving = false }
        do {
            // Even a draft may represent a timed-out server write: retain it until deletion is confirmed.
            try await api.deleteStickyNote(id: note.id)
            drafts.removeAll { $0.id == note.id }; notes.removeAll { $0.id == note.id }; persist(); status = nil
        } catch { status = "删除尚未确认，便利贴先保留。" }
    }
    private func persist() { defaults.set(try? JSONEncoder().encode(drafts), forKey: key) }
}
