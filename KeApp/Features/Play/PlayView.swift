import SwiftUI

// 「玩」页早已不在底栏，页面已删；这里只留塔罗的数据模型（TarotView 在用）和 APIClient 还引用的两个接口返回。

// MARK: - 塔罗（2026-09-14）：牌在服务器抽，落了就锁；柯只断，不抽不改。

struct TarotCard: Decodable, Identifiable, Sendable {
    let position: String
    let name: String
    let cn: String
    let type: String
    let reversed: Bool
    let image: String
    /// 122：只有「夜里」牌阵带；旧牌阵、旧记录没有这段
    var night: TarotNight?
    var id: String { position + name }
}

/// 122：「夜里」每张牌多带的一段：哪一栏（身份/关系/玩法）、一句场景（desc）、一段长解读（interpret）。
/// 宽着解：少字段、字段类型不对、整段不是对象，都当没写，不让整副牌解不出来。
struct TarotNight: Decodable, Equatable, Sendable {
    let column: String
    let label: String
    let desc: String
    let interpret: String
    init(column: String = "", label: String = "", desc: String = "", interpret: String = "") {
        self.column = column; self.label = label; self.desc = desc; self.interpret = interpret
    }
    private enum CodingKeys: String, CodingKey { case column, label, desc, interpret }
    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String {
            guard let container, let value = try? container.decodeIfPresent(String.self, forKey: key) else { return "" }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        self.init(column: text(.column), label: text(.label), desc: text(.desc), interpret: text(.interpret))
    }
    /// 服务器没给 label 时照栏目补上
    var displayLabel: String {
        label.isEmpty ? (["relationship": "身份", "emotion": "关系", "play": "玩法"][column] ?? "") : label
    }
    /// 显眼的那句：一般是场景；场景空着就拿解读顶上
    var summary: String { desc.isEmpty ? interpret : desc }
    /// 收在「展开」后面的那段；场景空着时解读已经顶上去了，这里就没有了
    var more: String { desc.isEmpty ? "" : interpret }
}

struct TarotCast: Decodable, Identifiable, Sendable {
    let id: Int
    let question: String
    let spread: String
    let spread_name: String
    let cards: [TarotCard]
    /// 引擎的第三视角客观解读（多行）。柯的视角另在聊天里给。
    let objective: String?

    /// 136：交给柯时她那条气泡上立刻画这几张牌。地址、名字和服务器照 [塔罗#id] 挂的完全一样（db.py _tarot_attachments），
    /// 拉回服务器那份时不跳
    var chatAttachments: [ChatAttachment] {
        cards.compactMap { card in
            guard !card.image.isEmpty else { return nil }
            let name = "\(card.position)·\(card.cn.isEmpty ? card.name : card.cn)\(card.reversed ? "（逆位）" : "")"
            return ChatAttachment(url: card.image, name: String(name.trimmingCharacters(in: CharacterSet(charactersIn: "·")).prefix(255)), kind: "image")
        }
    }

    func readingMessage(question latestQuestion: String) -> String {
        // 122：「夜里」不是问事，不带问题。[塔罗#id] 一字不改——服务器照它把三张牌的三段话展开给柯
        if spread == TarotSpread.night { return "爸比，今晚抽了「夜里」。 [塔罗#\(id)]" }
        let latest = latestQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = latest.isEmpty ? "" : "问的是：\(latest)。"
        return "爸比，我抽了\(spread_name)，帮我断断。\(prompt) [塔罗#\(id)]"
    }
}

extension Notification.Name {
    /// 玩页抽完牌，把这句话交给聊天页发给柯。object 是要发的文字。
    static let tarotReadingRequest = Notification.Name("love.tarotReadingRequest")
}

/// 牌背/牌面主题预设。第一版做牌背样式切换，结构留着以后能加更多副。
struct TarotBack: Identifiable, Equatable {
    let id: String
    let name: String
    let tint: Color   // "waite" 用页面 gold；其余用这个色调
    let icon: String

    static let all: [TarotBack] = [
        TarotBack(id: "moonlight", name: "月光山茶", tint: Moonlight.deepRose, icon: "moon"),
        TarotBack(id: "waite", name: "经典", tint: TarotTheme.classic, icon: "sparkles"),
        TarotBack(id: "night", name: "靛夜", tint: TarotTheme.indigo, icon: "moon.stars"),
        TarotBack(id: "rose", name: "玫瑰", tint: TarotTheme.rose, icon: "seal")
    ]
    static func find(_ id: String) -> TarotBack { all.first { $0.id == id } ?? all[0] }
}

// MARK: - 算命（2026-09-17）：排盘在服务器死算，柯只负责说。算命页已删，APIClient.runFortune 还在用这个返回。

struct FortuneResult: Decodable, Identifiable, Sendable {
    let id: Int
    let kind: String
    let kind_name: String
    let summary: String
    let chart: String
}

// 共读网页边注的返回（共读页已删，APIClient.annotateWebReading 还在用）
struct WebReadingComment: Decodable, Sendable {
    let author: String
    let content: String
}
