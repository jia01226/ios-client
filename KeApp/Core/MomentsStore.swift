import Foundation
import Combine

struct MomentsActivity: Decodable, Sendable {
    let last_ke_activity_at: String
    let waiting: Bool
}

protocol MomentsAPI {
    func fetchMoments() async throws -> [RemoteMoment]
    func fetchMomentsActivity() async throws -> MomentsActivity
    func addMoment(content: String, image: String) async throws
    func setMomentLike(id: Int, liked: Bool) async throws
    func addMomentComment(id: Int, content: String) async throws
    func editMoment(id: Int, content: String) async throws
    func deleteMoment(id: Int) async throws
    func editMomentComment(id: Int, content: String) async throws
    func deleteMomentComment(id: Int) async throws
}
extension APIClient: MomentsAPI {}

@MainActor
final class MomentsStore: ObservableObject {
    @Published private(set) var moments: [RemoteMoment] = []
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published private(set) var error: String?
    @Published private(set) var hasUnread = false
    @Published private(set) var waiting = false
    var pollInterval: UInt64 { waiting ? 5_000_000_000 : 45_000_000_000 }
    private let api: any MomentsAPI
    private let defaults: UserDefaults
    private let seenKey: String
    private var revision = 0
    private var checkingActivity = false

    init(api: any MomentsAPI, scope: String, defaults: UserDefaults = .standard) {
        self.api = api; self.defaults = defaults
        seenKey = "moments.seen." + scope
    }

    func refreshActivity() async {
        guard !checkingActivity else { return }
        checkingActivity = true
        defer { checkingActivity = false }
        let current = revision
        do {
            let activity = try await api.fetchMomentsActivity()
            guard !Task.isCancelled, current == revision else { return }
            updateActivity(activity)
        } catch { /* A failed background check must not erase an existing dot. */ }
    }

    func load() async {
        guard !loading, !saving else { return }
        loading = true
        let current = revision
        defer { loading = false }
        // Sample before the list: activity arriving while the list is in flight stays unread.
        let activity = try? await api.fetchMomentsActivity()
        do {
            let rows = try await api.fetchMoments()
            guard !Task.isCancelled, current == revision else { return }
            moments = rows; error = nil
            if let activity {
                markSeen(activity.last_ke_activity_at)
                updateActivity(activity)
            }
        } catch {
            guard !Task.isCancelled, current == revision else { return }
            self.error = "朋友圈没有刷新成功，请下拉重试。"
        }
    }

    func publish(content: String, image: String) async -> Bool {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !image.isEmpty else { return false }
        return await write { try await self.api.addMoment(content: text, image: image) }
    }
    func like(_ moment: RemoteMoment) async {
        guard let current = moments.first(where: { $0.id == moment.id }) else { return }
        _ = await write { try await self.api.setMomentLike(id: current.id, liked: current.user_liked == 0) }
    }
    func comment(on moment: RemoteMoment, content: String) async -> Bool {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, moments.contains(where: { $0.id == moment.id }) else { return false }
        return await write { try await self.api.addMomentComment(id: moment.id, content: text) }
    }
    func edit(_ moment: RemoteMoment, content: String) async -> Bool {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, owns(moment) else { return false }
        return await write { try await self.api.editMoment(id: moment.id, content: text) }
    }
    func delete(_ moment: RemoteMoment) async -> Bool {
        guard owns(moment) else { return false }
        return await write { try await self.api.deleteMoment(id: moment.id) }
    }
    func editComment(_ comment: RemoteMomentComment, content: String) async -> Bool {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, owns(comment) else { return false }
        return await write { try await self.api.editMomentComment(id: comment.id, content: text) }
    }
    func deleteComment(_ comment: RemoteMomentComment) async -> Bool {
        guard owns(comment) else { return false }
        return await write { try await self.api.deleteMomentComment(id: comment.id) }
    }
    private func owns(_ moment: RemoteMoment) -> Bool {
        moment.author == "user" && moments.contains { $0.id == moment.id && $0.author == "user" }
    }
    private func owns(_ comment: RemoteMomentComment) -> Bool {
        comment.author == "user" && moments.flatMap(\.comments).contains { $0.id == comment.id && $0.author == "user" }
    }
    private func write(_ operation: () async throws -> Void) async -> Bool {
        guard !saving else { return false }
        saving = true; revision += 1; error = nil
        defer { saving = false }
        do { try await operation() }
        catch {
            self.error = "这次操作没有确认成功，内容已保留。请先刷新核对，再重试。"
            return false
        }
        // A confirmed write remains successful even if the follow-up read fails.
        // Do not encourage duplicate posts/comments by treating read failure as write failure.
        do { moments = try await api.fetchMoments() }
        catch { self.error = "已保存，列表暂时没有刷新成功，请下拉重试。" }
        return true
    }
    private func updateActivity(_ activity: MomentsActivity) {
        waiting = activity.waiting
        hasUnread = !activity.last_ke_activity_at.isEmpty && activity.last_ke_activity_at > (defaults.string(forKey: seenKey) ?? "")
    }
    private func markSeen(_ timestamp: String) {
        if timestamp > (defaults.string(forKey: seenKey) ?? "") { defaults.set(timestamp, forKey: seenKey) }
    }
}
