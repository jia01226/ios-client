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
    var layer: String? = nil
    var group: String? = nil
    var id: String { fact_id }
}

struct ReviewedFactsPage: Codable, Sendable {
    var store_id: String
    var facts: [ReviewedFact]
    var next_offset: Int?
}

enum MemoryFactBoundary {
    private static let behaviorKeys = ["提醒", "待办", "任务", "行为建议", "生活建议", "行动计划"]
    private static let directivePrefixes = [
        "记得", "别忘", "不要忘", "请记得", "要记得", "需要记得",
        "务必", "千万要", "应该", "应当", "该去", "该吃", "该睡",
        "早点睡", "按时吃药", "多喝水", "去吃饭", "去睡觉", "去休息",
    ]

    static func isReviewableFact(key: String, value: String) -> Bool {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else { return false }
        if behaviorKeys.contains(where: normalizedKey.contains) { return false }
        return !directivePrefixes.contains(where: normalizedValue.hasPrefix)
    }

    static func shelfTitle(key: String) -> String {
        if ["药", "用药", "服药", "剂量", "处方"].contains(where: key.contains) { return "我的药" }
        if ["喜好", "偏好", "喜欢", "不喜欢"].contains(where: key.contains) { return "我的喜好" }
        if ["关系", "约定", "相处", "称呼"].contains(where: key.contains) { return "关系" }
        return "生活"
    }
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
