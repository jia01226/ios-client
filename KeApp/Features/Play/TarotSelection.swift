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

struct TarotDeal: Decodable, Sendable {
    let deal_id: TarotDealID
    let deck_size: Int
    let spread: String
    let spread_name: String
    let positions: [String]
    var isValid: Bool {
        deck_size == 78 && positions.count == ["one": 1, "three": 3, "celtic": 10][spread]
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
    static let count = 78

    /// 第 index 张在牌扇里的中心点，和从扇心朝外的角度（弧度：π 最左，3π/2 正上，2π 最右）。
    static func placement(_ index: Int, width: CGFloat, height: CGFloat, lifted: Bool) -> (center: CGPoint, angle: Double) {
        let angle = Double.pi + Double(index) / Double(count - 1) * Double.pi
        let radius = Double(width * (TarotTableStyle.fanRadius + (lifted ? TarotTableStyle.previewLift : 0)))
        let center = CGPoint(x: width / 2 + CGFloat(cos(angle) * radius),
                             y: height - width * TarotTableStyle.fanBottom + CGFloat(sin(angle) * radius))
        return (center, angle)
    }

    /// 手指按在 point（牌桌坐标）上，看到的最上面那张是第几张；没按在牌上就是 nil。
    /// 叠的次序和画的一样：抬起的那张最上面，其余后面的盖住前面的；已经放上桌的不算。
    /// liftAware 为 false（左右滑着换牌）时当作都没抬起：抬起那张就挡不住手指往旁边换。
    static func card(at point: CGPoint, width: CGFloat, height: CGFloat,
                     picks: [Int], preview: Int?, liftAware: Bool = true) -> Int? {
        let halfWidth = Double(width * TarotTableStyle.fanCardWidth / 2)
        let halfLength = halfWidth / Double(TarotTableStyle.cardAspect)
        let slop = Double(TarotTableStyle.fanTouchSlop)
        let lifted = liftAware ? preview.flatMap { picks.contains($0) ? nil : $0 } : nil
        var order = Array((0..<count).reversed())
        if let lifted { order.removeAll { $0 == lifted }; order.insert(lifted, at: 0) }
        for index in order where !picks.contains(index) {
            let isLifted = index == lifted
            let (center, angle) = placement(index, width: width, height: height, lifted: isLifted)
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
