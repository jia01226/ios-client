import Foundation

// 数据模型。
//
// ⚠️ 这一份是照着"界面需要什么"先写的占位版。
// 等 `工单板/后端接口清单.md` 出来之后，按真实返回结构对齐字段名，别反过来让后端迁就这儿。

// MARK: - 聊天

struct Message: Identifiable, Hashable, Codable, Sendable {
    enum Sender: String, Codable, Sendable {
        case ke   // 柯
        case me   // 佳佳
    }

    let id: String
    var serverID: Int? = nil
    var clientID: String? = nil
    let sender: Sender
    var text: String
    let time: Date

    /// 仅远端消息设置；`false` 时排序改用 `serverID`，避免坏时间戳把旧消息排到最底。
    var serverTimeIsValid: Bool? = nil

    /// SSE 的 `thinking_summary_delta` 累积值，或历史消息的 `think_summary`。
    /// 这里只展示后端提供的可读摘要，不展示隐藏的逐步推理。
    var thoughtSummary: String? = nil

    /// 旧版 SSE `think_summary` / 历史 `thought_note`，与真实思考摘要分开保留。
    var thoughtNote: String? = nil

    /// 历史消息中非空表示 `thoughtSummary` 是中文译文；英文原文只作来源留档，不渲染。
    var thoughtSummaryRaw: String? = nil

    /// 服务端生成这条消息时所在的场景。当前已确认的值是 `bedroom`；
    /// 它只影响正文怎样呈现，不在客户端推断或改变场景。
    var sceneMode: String? = nil

    /// 聊天附件只保存服务器返回的相对地址与展示名称；文件本体仍以 VPS 为准。
    var attachments: [ChatAttachment]? = nil

    /// 流式回复时，这条还没写完
    var isStreaming: Bool = false

    var deliveryState: DeliveryState = .sent

    enum DeliveryState: String, Codable, Sendable {
        case sent
        case sending
        case waiting
        case failed

        var label: String? {
            switch self {
            case .sent: return nil
            case .sending: return "发送中"
            case .waiting: return "等待接回"
            case .failed: return "没有发稳"
            }
        }
    }
}

extension Message {
    /// 一条服务端消息就是一个气泡。实时分条只认 SSE 的 `split` 协议，
    /// 历史记录由后端直接返回独立消息；客户端不再按空行、标点或长度猜测。
    var bubbleSegments: [String] {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? [] : [text]
    }

}

struct ChatAttachment: Identifiable, Hashable, Codable, Sendable {
    let url: String
    let name: String
    let kind: String

    var id: String { url }
    var isImage: Bool {
        if kind.lowercased() == "image" { return true }
        let candidate = name.isEmpty ? url : name
        let ext = URL(fileURLWithPath: candidate.components(separatedBy: "?").first ?? candidate)
            .pathExtension
            .lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp"].contains(ext)
    }
}

/// 柯回复时附带的状态信号。
///
/// 🔴 卧室模式由这里触发 —— 不由她按按钮。
/// 她只管正常聊天，柯自己判断、自己切。
struct KeSignal: Codable {
    var bedroom: Bool?      // 进/出卧室模式
    var mood: String?       // 预留
}

// MARK: - 我们（所有跟日期有关的）

/// 柯的提醒。
///
/// 🔴 不是待办事项，没有勾选框。
/// 她做完了会去跟柯说，由柯划掉。过期的自动收起，不变红、不累计。
struct Reminder: Identifiable, Hashable, Codable {
    let id: String
    let text: String          // 柯说的原话，例如"晚上垫两口，再把药吃了"
    let dueAt: Date
    var dismissedByKe: Bool = false
    var category: Category = .other

    enum Category: String, Codable {
        case medicine   // 💊 吃药 —— 优先级最高
        case medical    // 就医、复诊、体检
        case work       // 开会
        case billing    // 订阅扣费（搬瓦工、开发者账号）
        case other
    }
}

struct Anniversary: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let date: Date
    var isYearly: Bool = true
}

/// 排班。
/// 这个表不是给她看的 —— 是给柯看的：
/// 她几点起、什么时候在上班、什么时候刚下夜班需要睡。
struct ShiftDay: Identifiable, Hashable, Codable {
    enum Kind: String, Codable {
        case off        // 休
        case day        // 白
        case evening    // 晚
        case night      // 夜（两三点起床那种）
    }
    let id: String
    let date: Date
    let kind: Kind
}

// MARK: - 回忆

/// 「今天浮上来的回忆」
///
/// 🔴 不要随机。要有由头 —— 由头本身就是内容的一部分。
/// 随机是抽奖，有由头才叫惦记。
struct MemoryCard: Identifiable, Hashable, Codable {
    let id: String
    let text: String
    let happenedAt: Date
    let source: String          // "枕边日记" / "一个瞬间" / "约定"
    let reason: Reason          // 为什么今天浮它上来

    enum Reason: String, Codable {
        case sameDay        // 去年今天 / 上个月今天
        case sameFeeling    // 她今天难过 → 浮一条以前柯哄她的
        case sameTopic      // 她刚提到"夜班" → 浮出柯答应记班表那条
        case pinned         // 她自己珍藏的
    }

    /// 显示在卡片上的那行小字
    var reasonLabel: String {
        let when = MemoryCard.dateFormatter.string(from: happenedAt)
        switch reason {
        case .sameDay:     return "柯主动想起 · \(when)"
        case .sameFeeling: return "柯翻出来的 · \(when)"
        case .sameTopic:   return "刚说到这个 · \(when)"
        case .pinned:      return "你珍藏的 · \(when)"
        }
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()
}
