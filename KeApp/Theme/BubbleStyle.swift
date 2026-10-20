import SwiftUI

/// 127：她自己挑气泡——「我的气泡」「柯的气泡」各一排颜色、各一条浓度。
/// 气泡只是一块不透明度可调的纯色（加一道 0.5pt 白边、底下一线很淡的影子），
/// 不再每个气泡垫一层实时玻璃/模糊：滑聊天时每帧不用重新采样底下的东西。
enum BubbleSide: String, CaseIterable, Identifiable {
    case me, ke
    var id: String { rawValue }
    var title: String { self == .me ? "我的气泡" : "柯的气泡" }
}

struct BubbleSwatch: Identifiable, Equatable {
    let id: String
    let name: String
    let me: UInt32
    let ke: UInt32

    func hex(for side: BubbleSide) -> UInt32 { side == .me ? me : ke }

    /// 第一个是默认：设计稿那块淡粉（她）/ 近白（柯）；「月光浅粉」就是 125 和以前的那两种粉。
    static let all: [BubbleSwatch] = [
        .init(id: "blush", name: "粉白", me: 0xF6E8EC, ke: 0xFFFFFF),
        .init(id: "moonlight", name: "月光浅粉", me: Morandi.own, ke: Morandi.reply),
        .init(id: "cream", name: "奶白", me: 0xFBF5EC, ke: 0xFFFCF6),
        .init(id: "mist", name: "雾粉", me: 0xE6C6D0, ke: 0xF5E4E7),
        .init(id: "oat", name: "燕麦", me: 0xD7CAB6, ke: 0xEDE7DE),
    ]

    static func matching(_ hex: UInt32, side: BubbleSide) -> BubbleSwatch? {
        all.first { $0.hex(for: side) == hex }
    }
}

/// 存在 UserDefaults 里的四个值。旧的「气泡透明度 0–6%」不搬过来（那是给玻璃染色用的，跟浓度不是一回事），
/// 它还留给夜里、卧室、照片壁纸那几种原来的玻璃气泡用。
enum BubbleStyleStore {
    static let meColorKey = "app.bubble127.me.color"
    static let keColorKey = "app.bubble127.ke.color"
    static let meDensityKey = "app.bubble127.me.density"
    static let keDensityKey = "app.bubble127.ke.density"

    /// 默认照设计稿在屏幕上的样子：她的淡粉约 70%，柯的近白约 60%
    static let defaultMeDensity = 0.70
    static let defaultKeDensity = 0.60

    static func colorKey(_ side: BubbleSide) -> String { side == .me ? meColorKey : keColorKey }
    static func densityKey(_ side: BubbleSide) -> String { side == .me ? meDensityKey : keDensityKey }
    static func defaultHex(_ side: BubbleSide) -> UInt32 { BubbleSwatch.all[0].hex(for: side) }
    static func defaultDensity(_ side: BubbleSide) -> Double { side == .me ? defaultMeDensity : defaultKeDensity }

    static func loadHex(_ side: BubbleSide, _ defaults: UserDefaults = .standard) -> UInt32 {
        guard let value = defaults.object(forKey: colorKey(side)) as? Int, value >= 0, value <= 0xFFFFFF else {
            return defaultHex(side)
        }
        return UInt32(value)
    }

    static func loadDensity(_ side: BubbleSide, _ defaults: UserDefaults = .standard) -> Double {
        guard let value = defaults.object(forKey: densityKey(side)) as? Double, value.isFinite else {
            return defaultDensity(side)
        }
        return min(max(value, 0), 1)
    }
}

extension Color {
    /// 系统取色盘挑出来的颜色 → 0xRRGGBB（不要透明度）
    var rgbHex: UInt32? {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}

/// 聊天里和设置预览里画气泡底的同一块：纯色 × 浓度、白边、底下一线淡影。
/// 影子不用 .shadow（那个在每个格子上要离屏算），用往下挪一点的一道淡墨边代替，滑动时是静止的位图。
struct BubbleFill: View {
    let color: Color
    let density: Double
    let ink: Color
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            // 一线贴着下沿的淡墨边，当很轻的影子
            shape.stroke(ink.opacity(0.07), lineWidth: 1).offset(y: 0.75)
            // 「降低透明度」开着就画实心（和设计稿一样），浓度只在平时管用
            shape.fill(color.opacity(reduceTransparency ? 1 : density))
            shape.strokeBorder(
                reduceTransparency ? ink.opacity(0.25) : Color.white.opacity(0.85),
                lineWidth: reduceTransparency ? 0.75 : 0.5
            )
        }
        .allowsHitTesting(false)
    }
}
