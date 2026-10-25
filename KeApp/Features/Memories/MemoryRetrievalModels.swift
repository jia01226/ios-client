import Foundation

// 记忆检索的接口模型。检索页（只能从旧 MemoriesView 进）已删，APIClient 还在用这些。
struct MemoryRetrievalCandidate: Decodable, Identifiable {
    let id: String
    let fact: String
    let quote: String
    let note: String
    let occurred_at: String
    let selected: Bool
    let reason: String
    let keyword_rank: Int?
    let semantic_rank: Int?
    let similarity: Double?
}
struct MemoryRetrievalSemantic: Decodable {
    let status: String
    let eligible: Int?
    let indexed: Int?
}
struct MemoryRetrievalTrace: Decodable, Identifiable {
    let id: String
    let created_at: String
    let query: String
    let session_id: String
    let stage: String
    let fact_count: Int
    let candidates: [MemoryRetrievalCandidate]
    let raw_event_ids: [String]
    let semantic: MemoryRetrievalSemantic
    var change_guard_count: Int? = nil
}
struct MemoryRetrievalReport: Decodable {
    let recent: [MemoryRetrievalTrace]
    let notice: String
}

enum MemoryFeedbackKind: String, CaseIterable, Identifiable {
    case missing
    case memoryOutdated = "memory_outdated"
    case memoryWrong = "memory_wrong"
    case answerWrong = "answer_wrong"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .missing: return "没找到该记忆"
        case .memoryOutdated: return "记忆已经过期"
        case .memoryWrong: return "记忆内容不对"
        case .answerWrong: return "记忆正确，柯答错了"
        }
    }
    var needsCandidate: Bool { self == .memoryOutdated || self == .memoryWrong }
}

struct MemoryFeedbackReceipt: Decodable {
    let saved: Bool
    let id: String
    let patch_id: String?
    let result: String
}
