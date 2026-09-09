import Foundation

struct ReviewSource: Codable, Equatable, Identifiable, Sendable {
    var event_id: String
    var channel: String
    var session_id: String
    var role: String
    var content_raw: String
    var occurred_at: String?
    var source_locator: String
    var id: String { event_id }
    var label: String {
        switch channel {
        case "app": return "App"
        case "cc": return "CC"
        case "manual": return "App 审核"
        case "wechat": return "微信"
        default: return channel
        }
    }
}

struct ReviewCard: Codable, Equatable, Identifiable, Sendable {
    var patch_id: String
    var fact: String
    var category: String
    var fact_key: String
    var quote: String
    var sources: [ReviewSource]
    var observed_at: String
    var status: String
    var revision: Int
    var note: String
    var deferred: Bool
    var can_accept: Bool
    var validation: [String]
    var id: String { patch_id }
}

struct ReviewPage: Codable, Sendable {
    var store_id: String
    var cards: [ReviewCard]
    var next_offset: Int?
}

struct ReviewedFactHistory: Codable, Identifiable, Sendable {
    var id: String
    var fact: String
    var quote: String
    var observed_at: String
    var note: String
}

struct ReviewedFact: Codable, Identifiable, Sendable {
    var fact_id: String
    var fact: String
    var quote: String
    var category: String
    var observed_at: String
    var note: String
    var review_card: ReviewCard? = nil
    var history: [ReviewedFactHistory]? = nil
    var changed_when: String? = nil
    var id: String { fact_id }
}

struct ReviewedFactsPage: Codable, Sendable {
    var store_id: String
    var facts: [ReviewedFact]
    var next_offset: Int?
}

struct ReviewStats: Codable, Sendable {
    var store_id: String
    var pending: Int
    var accepted: Int
    var rejected: Int
}

enum ReviewAction: String, Codable, Sendable {
    case accept, reject, note, `defer`, undo, changed
    var label: String {
        switch self {
        case .accept: return "收下"
        case .reject: return "不对"
        case .note: return "保存备注"
        case .defer: return "暂缓"
        case .undo: return "撤销"
        case .changed: return "情况变了"
        }
    }
}

struct ReviewOperation: Codable, Identifiable, Sendable {
    var store_id: String
    var operation_id: String
    var patch_id: String
    var revision: Int
    var verdict: ReviewAction
    var note: String
    var new_fact: String? = nil
    var changed_when: String? = nil
    var undo_operation_id: String?
    var id: String { operation_id }
}

struct ReviewReceipt: Codable, Sendable {
    var store_id: String
    var operation_id: String
    var card: ReviewCard
}

protocol MemoryReviewService: Sendable {
    func reviewPending(offset: Int) async throws -> ReviewPage
    func submitReview(_ operation: ReviewOperation) async throws -> ReviewReceipt
    func reviewStats() async throws -> ReviewStats
    func reviewedFacts(offset: Int) async throws -> ReviewedFactsPage
}

struct ReviewUndo: Codable {
    var operation: ReviewOperation
    var before: ReviewCard
}

struct MemoryChangeDraft: Codable {
    var fact: String = ""
    var when: String = ""
}

struct ReviewArchive: Codable {
    var changeDrafts: [String: MemoryChangeDraft]? = nil
    var storeID: String?
    var cards: [ReviewCard] = []
    var outbox: [ReviewOperation] = []
    var undo: ReviewUndo?
    var drafts: [String: String] = [:]
    var facts: [ReviewedFact] = []
    var needsReconciliation = false
}

struct ReviewGesture {
    static func action(x: CGFloat, y: CGFloat, threshold: CGFloat = 100) -> ReviewAction? {
        if abs(x) > abs(y), abs(x) >= threshold { return x > 0 ? .accept : .reject }
        if y <= -threshold, abs(y) > abs(x) { return .defer }
        if y >= threshold, abs(y) > abs(x) { return .changed }
        return nil
    }
}
