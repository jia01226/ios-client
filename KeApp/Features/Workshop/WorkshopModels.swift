import Foundation

// 145：工坊——App 里另开的那扇 Claude Code 窗（2026-11-03 她：「两条线分开，app 多一个 cc 窗口，
// 有你一样的权限，可以去改东西、联网搜索，然后柯也知道进度」）。跟柯的聊天完全分开，接口是 /api/workshop/*。

struct WorkshopTraceItem: Decodable, Equatable, Sendable {
    let t: String?
    let tool: String?
    let brief: String?
    let error: String?
}

struct WorkshopMessage: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let role: String          // user / assistant / divider
    let origin: String        // her / ke（柯转来的单子）/ workshop
    let content: String
    let trace: [WorkshopTraceItem]
    let to_ke: String
    let model: String
    let status: String        // sent / queued / done / error / stopped
    let created_at: String
}

struct WorkshopChoice: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let account: Int          // 1、2 是 Claude 号；0 是 DeepSeek
    let web_search: Bool
}

struct WorkshopJob: Decodable, Equatable, Sendable {
    let id: String
    let status: String
    let model: String
    let message_id: Int
}

struct WorkshopQuotaWindow: Decodable, Equatable, Sendable {
    let used: Int
    let reset_at: Int
}

struct WorkshopSnapshot: Decodable, Equatable, Sendable {
    let messages: [WorkshopMessage]
    let job: WorkshopJob?
    let model: String
    let choices: [WorkshopChoice]
    let quota: [String: [String: WorkshopQuotaWindow]]
}

struct WorkshopSendResult: Decodable, Equatable, Sendable {
    let queued: Bool
    let message_id: Int
    let job_id: String?
}

/// 事件流里的一条：字、一步工具、某步出错、结束、让 App 带着 seq 再连。
struct WorkshopEvent: Equatable, Sendable {
    enum Kind: String, Sendable { case text, tool, toolError = "tool_error", done, reconnect }
    let kind: Kind
    let seq: Int
    var text = ""
    var tool = ""
    var id = ""
    var status = ""
    var toKe = ""
    var error = ""

    init(kind: Kind, seq: Int) {
        self.kind = kind
        self.seq = seq
    }

    init?(json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["type"] as? String, let kind = Kind(rawValue: raw) else { return nil }
        self.kind = kind
        self.seq = obj["seq"] as? Int ?? 0
        text = obj["t"] as? String ?? ""
        tool = obj["tool"] as? String ?? ""
        id = obj["id"] as? String ?? ""
        status = obj["status"] as? String ?? ""
        toKe = obj["to_ke"] as? String ?? ""
        error = (obj["error"] as? String) ?? (kind == .toolError ? (obj["brief"] as? String ?? "") : "")
        if kind == .tool { text = obj["brief"] as? String ?? "" }
    }
}

/// 工具名换成她看得懂的话和图标
enum WorkshopToolName {
    static func label(_ tool: String) -> String {
        switch tool {
        case "Bash": return "跑命令"
        case "Read": return "看文件"
        case "Edit", "MultiEdit", "NotebookEdit": return "改文件"
        case "Write": return "写文件"
        case "Grep": return "搜代码"
        case "Glob": return "找文件"
        case "WebSearch": return "上网搜"
        case "WebFetch": return "打开网页"
        case "TodoWrite": return "列计划"
        case "Agent", "Task": return "叫帮手"
        default: return tool
        }
    }

    static func icon(_ tool: String) -> String {
        switch tool {
        case "Bash": return "terminal"
        case "Read": return "doc.text"
        case "Edit", "MultiEdit", "NotebookEdit": return "pencil"
        case "Write": return "square.and.pencil"
        case "Grep", "Glob": return "magnifyingglass"
        case "WebSearch": return "globe"
        case "WebFetch": return "safari"
        case "TodoWrite": return "checklist"
        case "Agent", "Task": return "person.2"
        default: return "wrench.and.screwdriver"
        }
    }
}

/// 136 那样，把小本子要跟服务器说的几样抽成协议，测试里换成假的
protocol WorkshopAPI: Sendable {
    func fetchWorkshop() async throws -> WorkshopSnapshot
    func sendWorkshop(text: String, model: String?) async throws -> WorkshopSendResult
    func workshopEvents(jobID: String, after: Int) async throws -> AsyncThrowingStream<WorkshopEvent, Error>
    func stopWorkshop() async throws
    func setWorkshopModel(_ id: String) async throws
    func newWorkshop() async throws
}
extension APIClient: WorkshopAPI {}
