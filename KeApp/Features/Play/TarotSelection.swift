import Foundation
import CoreGraphics

/// Keep opaque deal IDs in their original wire type, including older numeric IDs.
enum TarotDealID: Codable, Equatable, Sendable {
    case text(String)
    case number(Int)
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let text = try? value.decode(String.self) { self = .text(text) }
        else { self = .number(try value.decode(Int.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self { case .text(let id): try value.encode(id); case .number(let id): try value.encode(id) }
    }
}

/// 122：牌阵。原来「一张/三张/凯尔特十字」和 78 张散在各处写死，加「夜里」后收到这一处。
/// 夜里是两个人今晚的角色扮演：只用 22 张大牌、三个位置（身份/关系/玩法），不问问题。
enum TarotSpread {
    static let night = "night"
    static let all = ["one", "three", "celtic", night]
    static func title(_ key: String) -> String {
        ["one": "一张", "three": "三张", "celtic": "凯尔特十字", night: "夜里"][key] ?? key
    }
    static func cardCount(_ key: String) -> Int? { ["one": 1, "three": 3, "celtic": 10, night: 3][key] }
    static func deckSize(_ key: String) -> Int { key == night ? 22 : TarotFan.count }
    /// 洗牌前桌上先摆的位置名；洗完以服务器给的为准
    static func positions(_ key: String) -> [String] {
        switch key {
        case "one": return ["此刻"]
        case "celtic": return (1...10).map { "\($0)" }
        case night: return ["过去·身份", "现在·关系", "未来·玩法"]
        default: return ["过去", "现在", "未来"]
        }
    }
    /// 夜里不是算命，不填问题
    static func asksQuestion(_ key: String) -> Bool { key != night }
}

struct TarotDeal: Decodable, Sendable {
    let deal_id: TarotDealID
    let deck_size: Int
    let spread: String
    let spread_name: String
    let positions: [String]
    var isValid: Bool {
        // 122：夜里那副只有 22 张，别的照旧 78 张
        deck_size == TarotSpread.deckSize(spread) && positions.count == TarotSpread.cardCount(spread)
            && positions.allSatisfy { !$0.isEmpty }
    }
}

struct TarotPickRequest: Encodable {
    let deal_id: TarotDealID
    let picks: [Int]
}

/// Selection order is the server's position order. Previewing never adds a pick.
struct TarotSelection: Equatable {
    let deckSize: Int
    let requiredCount: Int
    private(set) var picks: [Int] = []
    private(set) var preview: Int?
    private(set) var submitted = false
    var isFull: Bool { picks.count == requiredCount }

    mutating func tap(_ index: Int) {
        guard !submitted, !isFull, (0..<deckSize).contains(index), !picks.contains(index) else { return }
        if preview == index { picks.append(index); preview = nil }
        else { preview = index }
    }
    mutating func previewCard(_ index: Int) {
        guard !submitted, !isFull, (0..<deckSize).contains(index), !picks.contains(index) else { return }
        preview = index
    }
    mutating func returnCard(_ index: Int) {
        guard !submitted else { return }
        picks.removeAll { $0 == index }
        preview = nil
    }
    /// A timed-out POST may already have succeeded. Freeze the exact request for retries.
    mutating func freeze() -> Bool {
        guard isFull else { return false }
        submitted = true; preview = nil
        return true
    }
}

/// 120：佳佳说塔罗「很容易误触到别的牌」。78 张叠成半圆，每张只露出 5 点宽的一条；
/// 以前按「手指的角度离哪张的中线最近」认牌，可眼睛看到的最上面那张总在它右边三四张，
/// 抬起来的就不是她按的那张；第二下点在抬起那张身上，也只有一两成能点中，别的都换成了旁边的牌。
/// 现在画牌和认牌用同一套摆法：从最上面那张往下找，第一张盖住手指的就是她按的。
enum TarotFan {
    /// 整副 78 张。122：「夜里」那副只有 22 张大牌——摆法和认牌都按这一副实际几张摊满半圆，
    /// 张数少了每张就露得宽一些（22 张时每张露出约 17 点，78 张时约 5 点），认牌规矩不变。
    static let count = 78
    /// 10-31 她：「很多想选的牌选不到，很细太小，点不到」。78 张挤一个半圆每张只露 5 点。
    /// 改成半圆里一次摊 24 张（每张露 16～18 点），左右滑转动牌扇，转得到每一张。夜里 22 张一屏摊得下，不用转。
    static let visibleCount = 24
    static func visible(deckSize: Int) -> Int { min(deckSize, visibleCount) }
    /// 牌扇最多转多少张：第 shift 张在最左边
    static func maxShift(deckSize: Int) -> Double { Double(max(deckSize - visible(deckSize: deckSize), 0)) }
    /// 这张现在在不在半圆里（转到外面的不画、不认）
    static func onFan(_ index: Int, deckSize: Int, visible: Int, shift: Double) -> Bool {
        let at = Double(index) - shift
        return at > -0.6 && at < Double(max(visible, 1) - 1) + 0.6
    }

    /// 第 index 张在牌扇里的中心点，和从扇心朝外的角度（弧度：π 最左，3π/2 正上，2π 最右）。
    /// visible 不传就是整副摊满半圆；shift 是牌扇转过了几张。
    static func placement(_ index: Int, width: CGFloat, height: CGFloat, lifted: Bool,
                          deckSize: Int = count, visible: Int? = nil, shift: Double = 0) -> (center: CGPoint, angle: Double) {
        let angle = Double.pi + (Double(index) - shift) / Double(max((visible ?? deckSize) - 1, 1)) * Double.pi
        let radius = Double(width * (TarotTableStyle.fanRadius + (lifted ? TarotTableStyle.previewLift : 0)))
        let center = CGPoint(x: width / 2 + CGFloat(cos(angle) * radius),
                             y: height - width * TarotTableStyle.fanBottom + CGFloat(sin(angle) * radius))
        return (center, angle)
    }

    /// 手指按在 point（牌桌坐标）上，看到的最上面那张是第几张；没按在牌上就是 nil。
    /// 叠的次序和画的一样：抬起的那张最上面，其余后面的盖住前面的；已经放上桌的不算。
    /// liftAware 为 false（左右滑着换牌）时当作都没抬起：抬起那张就挡不住手指往旁边换。
    static func card(at point: CGPoint, width: CGFloat, height: CGFloat,
                     picks: [Int], preview: Int?, liftAware: Bool = true, deckSize: Int = count,
                     visible: Int? = nil, shift: Double = 0) -> Int? {
        let halfWidth = Double(width * TarotTableStyle.fanCardWidth / 2)
        let halfLength = halfWidth / Double(TarotTableStyle.cardAspect)
        let slop = Double(TarotTableStyle.fanTouchSlop)
        let deck = 0..<max(deckSize, 0)
        let lifted = liftAware ? preview.flatMap { picks.contains($0) || !deck.contains($0) ? nil : $0 } : nil
        var order = Array(deck.reversed())
        if let lifted { order.removeAll { $0 == lifted }; order.insert(lifted, at: 0) }
        for index in order where !picks.contains(index) && onFan(index, deckSize: deckSize, visible: visible ?? deckSize, shift: shift) {
            let isLifted = index == lifted
            let (center, angle) = placement(index, width: width, height: height, lifted: isLifted, deckSize: deckSize, visible: visible, shift: shift)
            let dx = Double(point.x - center.x), dy = Double(point.y - center.y)
            // 牌的长边顺着扇心往外：沿 angle 是长，横过来是宽
            let along = dx * cos(angle) + dy * sin(angle)
            let across = -dx * sin(angle) + dy * cos(angle)
            let extra = isLifted ? Double(TarotTableStyle.liftedTouchSlop) : 0
            if abs(across) <= halfWidth + extra, abs(along) <= halfLength + slop + extra { return index }
        }
        return nil
    }
}
