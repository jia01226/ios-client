import Foundation
import CryptoKit
import Network

@MainActor
final class MemoryReviewStore: ObservableObject {
    @Published private(set) var archive = ReviewArchive()
    @Published private(set) var isSyncing = false
    @Published private(set) var error: String?
    @Published private(set) var blockedOperation: ReviewOperation?
    @Published private(set) var hasLoaded = false
    @Published private(set) var stats: ReviewStats?
    let line: ChatLine
    private let service: any MemoryReviewService
    private let file: URL
    private var storageReadable = true
    private var generation = 0
    private var monitor: NWPathMonitor?

    init(line: ChatLine, service: (any MemoryReviewService)? = nil, file: URL? = nil, watchNetwork: Bool = true) {
        self.line = line
        self.service = service ?? APIClient(baseURL: line.apiBaseURL)
        let key = SHA256.hash(data: Data(line.apiBaseURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MemoryReview/\(key).json")
        if FileManager.default.fileExists(atPath: self.file.path) {
            do {
                archive = try JSONDecoder().decode(ReviewArchive.self, from: Data(contentsOf: self.file))
            } catch {
                storageReadable = false
                self.error = "本机审卡记录未能读取，已保留原文件。请暂缓审核。"
            }
        }
        if watchNetwork {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in await self?.sync() }
            }
            monitor.start(queue: DispatchQueue(label: "memory-review-network-\(line.rawValue)"))
            self.monitor = monitor
        }
    }

    deinit { monitor?.cancel() }

    var pending: [ReviewCard] { archive.cards.filter { ["pending", "held"].contains($0.status) && !$0.deferred } }
    var deferred: [ReviewCard] { archive.cards.filter { ["pending", "held"].contains($0.status) && $0.deferred } }
    var canUndo: Bool { archive.undo != nil && storageReadable && blockedOperation == nil && !archive.needsReconciliation }
    var canReview: Bool { archive.storeID != nil && storageReadable && blockedOperation == nil && !archive.needsReconciliation }
    var syncLabel: String {
        if archive.needsReconciliation { return "等待核对服务器记录" }
        if !archive.outbox.isEmpty { return "\(archive.outbox.count) 项已存本机，待同步" }
        if isSyncing { return "正在同步" }
        if archive.cards.contains(where: { hasDraft(for: $0) }) { return "有备注草稿尚未提交" }
        return hasLoaded ? "已同步" : "等待连接"
    }

    private func persist(_ next: ReviewArchive) throws {
        guard storageReadable else { throw APIError.serverMessage("本机审卡记录暂时无法读取。") }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        archive = next
        generation += 1
    }

    func draft(for card: ReviewCard) -> String { archive.drafts[card.id] ?? card.note }
    func hasDraft(for card: ReviewCard) -> Bool {
        guard let draft = archive.drafts[card.id] else { return false }
        return draft != card.note
    }

    func saveDraft(_ text: String, for card: ReviewCard) {
        var next = archive
        next.drafts[card.id] = text
        do { try persist(next) } catch { self.error = "备注没能存到本机，请保留输入内容后重试。" }
    }

    @discardableResult
    func act(_ action: ReviewAction, on card: ReviewCard, note: String) -> Bool {
        guard canReview, let storeID = archive.storeID,
              let index = archive.cards.firstIndex(where: { $0.id == card.id }),
              archive.cards[index].revision == card.revision else { return false }
        if action == .accept && !card.can_accept { error = "请先核对这张卡的来源。"; return false }
        if action == .defer && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "写下不确定的地方，再向上划暂缓。"; return false
        }
        if note.count > 4000 { error = "备注最多写 4000 字，请缩短后保存。"; return false }
        let operation = ReviewOperation(store_id: storeID, operation_id: UUID().uuidString,
            patch_id: card.id, revision: card.revision, verdict: action, note: note)
        var next = archive
        next.outbox.append(operation)
        next.undo = ReviewUndo(operation: operation, before: card)
        next.cards[index].revision += 1
        next.cards[index].note = note
        next.drafts.removeValue(forKey: card.id)
        switch action {
        case .accept: next.cards[index].status = "applied"
        case .reject: next.cards[index].status = "rejected"
        case .defer: next.cards[index].deferred = true
        default: break
        }
        do { try persist(next); error = nil; return true }
        catch { self.error = "这次操作没能存到本机，请重试。"; return false }
    }

    func undo() {
        guard canUndo, let undo = archive.undo else { return }
        var next = archive
        guard let index = next.cards.firstIndex(where: { $0.id == undo.before.id }) else { return }
        let revision = next.cards[index].revision
        next.outbox.append(ReviewOperation(store_id: undo.operation.store_id, operation_id: UUID().uuidString,
            patch_id: undo.before.id, revision: revision, verdict: .undo, note: "",
            undo_operation_id: undo.operation.id))
        next.cards[index] = undo.before
        next.cards[index].revision = revision + 1
        next.cards.remove(at: index)
        next.cards.insert({ var value = undo.before; value.revision = revision + 1; return value }(), at: 0)
        next.undo = nil
        do { try persist(next); error = nil } catch { self.error = "撤销没有保存成功，请重试。" }
    }

    func sync() async {
        guard !isSyncing, storageReadable, blockedOperation == nil else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            while let operation = archive.outbox.first {
                let receipt: ReviewReceipt
                do { receipt = try await service.submitReview(operation) }
                catch APIError.badStatus(let code, let message) where (400..<500).contains(code) && code != 408 && code != 429 {
                    blockedOperation = operation
                    error = message.isEmpty ? "这次操作未能同步，请核对待同步记录。" : message
                    return
                }
                guard receipt.store_id == operation.store_id, receipt.operation_id == operation.id,
                      receipt.card.id == operation.patch_id, receipt.card.revision == operation.revision + 1 else {
                    throw APIError.invalidResponse
                }
                var next = archive
                next.outbox.removeFirst()
                if !next.outbox.contains(where: { $0.patch_id == operation.patch_id }),
                   let index = next.cards.firstIndex(where: { $0.id == operation.patch_id }) {
                    next.cards[index] = receipt.card
                }
                try persist(next)
            }
            let started = generation
            var cards: [ReviewCard] = []
            var offset = 0
            var storeID: String?
            repeat {
                let page = try await service.reviewPending(offset: offset)
                if let storeID, storeID != page.store_id { throw APIError.invalidResponse }
                storeID = page.store_id
                cards += page.cards
                guard let next = page.next_offset else { break }
                guard next > offset else { throw APIError.invalidResponse }
                offset = next
            } while true
            let remoteStats = try await service.reviewStats()
            var allFacts: [ReviewedFact] = []
            var factOffset = 0
            repeat {
                let page = try await service.reviewedFacts(offset: factOffset)
                guard storeID == page.store_id else { throw APIError.invalidResponse }
                allFacts += page.facts
                guard let nextOffset = page.next_offset else { break }
                guard nextOffset > factOffset else { throw APIError.invalidResponse }
                factOffset = nextOffset
            } while true
            guard storeID == remoteStats.store_id else { throw APIError.invalidResponse }
            // 网络请求期间新发生的本地操作拥有优先权。
            guard started == generation else {
                Task { await self.sync() }
                return
            }
            var next = archive
            if next.storeID != storeID { next.undo = nil; next.drafts = [:] }
            next.storeID = storeID
            if let undo = next.undo, !cards.contains(where: { $0.id == undo.before.id }),
               let cached = next.cards.first(where: { $0.id == undo.before.id }) { cards.append(cached) }
            next.cards = cards
            next.facts = allFacts
            next.needsReconciliation = false
            try persist(next)
            stats = remoteStats
            hasLoaded = true
            error = nil
        } catch { self.error = "同步未完成。已存本机的操作会保留，联网后可重试。" }
    }

    func discardBlockedOperation() async {
        guard let blocked = blockedOperation else { return }
        var next = archive
        // 同卡后续操作依赖被拒绝的版本；一起撤回本地判定，文字继续保留。
        next.needsReconciliation = true
        let affected = next.outbox.filter { $0.patch_id == blocked.patch_id }
        if let lastNote = affected.last(where: { !$0.note.isEmpty })?.note { next.drafts[blocked.patch_id] = lastNote }
        next.outbox.removeAll { $0.patch_id == blocked.patch_id }
        next.undo = nil
        do { try persist(next); blockedOperation = nil; await sync() }
        catch { self.error = "本机记录没能更新，请重试。" }
    }
}
