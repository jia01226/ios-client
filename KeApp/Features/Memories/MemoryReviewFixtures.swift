import Foundation

extension MemoryReviewStore {
    static func make(line: ChatLine) -> MemoryReviewStore {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-test-memory-review") {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("review-fixture-\(line.rawValue).json")
            try? FileManager.default.removeItem(at: url)
            return MemoryReviewStore(line: line, service: MemoryReviewFixtureService(), file: url, watchNetwork: false)
        }
#endif
        return MemoryReviewStore(line: line)
    }
}

#if DEBUG
actor MemoryReviewFixtureService: MemoryReviewService {
    static let sample = ReviewCard(patch_id: "sample-1", fact: "喜欢有酸味的蓝莓果酱", category: "喜好", fact_key: "喜好·食物",
        quote: "我喜欢有酸味的蓝莓果酱。", sources: [ReviewSource(event_id: "source-1", channel: "app", session_id: "1", role: "user",
        content_raw: "我喜欢有酸味的蓝莓果酱。今天试的这罐甜了一点。\n完整原文到这里结束。", occurred_at: "2026-09-08 10:00:00", source_locator: "fixture:1")],
        observed_at: "2026-09-08 10:00:00", status: "pending", revision: 0, note: "", deferred: false, can_accept: true, validation: [])
    var cards: [ReviewCard] = {
        var second = sample; second.patch_id = "sample-2"; second.fact = "周末想试试陶艺"; second.quote = "周末想试试陶艺。"
        second.sources[0].content_raw = "周末想试试陶艺，还没有预约。"; second.category = "生活"
        return [sample, second]
    }()
    var receipts: [String: ReviewReceipt] = [:]
    var before: [String: ReviewCard] = [:]

    func reviewPending(offset: Int) async throws -> ReviewPage {
        ReviewPage(store_id: "fixture-store", cards: cards.filter { $0.status == "pending" }, next_offset: nil)
    }
    func submitReview(_ operation: ReviewOperation) async throws -> ReviewReceipt {
        if let receipt = receipts[operation.id] { return receipt }
        let i = cards.firstIndex { $0.id == operation.patch_id }!
        before[operation.id] = cards[i]
        switch operation.verdict {
        case .accept: cards[i].status = "applied"
        case .reject: cards[i].status = "rejected"
        case .defer: cards[i].deferred = true
        case .undo: if let previous = before[operation.undo_operation_id ?? ""] { cards[i] = previous }
        case .note: break
        }
        cards[i].revision = operation.revision + 1
        if operation.verdict != .undo { cards[i].note = operation.note }
        let receipt = ReviewReceipt(store_id: "fixture-store", operation_id: operation.id, card: cards[i])
        receipts[operation.id] = receipt
        return receipt
    }
    func reviewStats() async throws -> ReviewStats {
        ReviewStats(store_id: "fixture-store", pending: cards.filter { $0.status == "pending" }.count,
            accepted: cards.filter { $0.status == "applied" }.count, rejected: cards.filter { $0.status == "rejected" }.count)
    }
    func reviewedFacts(offset: Int) async throws -> ReviewedFactsPage {
        ReviewedFactsPage(store_id: "fixture-store", facts: cards.filter { $0.status == "applied" }.map {
            ReviewedFact(fact_id: $0.id, fact: $0.fact, quote: $0.quote, category: $0.category, observed_at: $0.observed_at, note: $0.note)
        }, next_offset: nil)
    }
}
#endif
