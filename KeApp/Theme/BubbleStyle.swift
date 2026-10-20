import SwiftUI

/// 127：她自己挑气泡——「我的气泡」「柯的气泡」各一排颜色、各一条浓度。
/// 128 她：「消息的边界感太重了，你就做成QQ那个样子吧，然后我自定义颜色」。
/// 气泡就是一整块平的圆角纯色：没有白边、没有影子线、没有高光，浓度默认 100%（实心）。
/// 她挑了深色，上面的字自动换成白的。
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
        // 128：她的粉比 127 深一点点（实心以后 F6E8EC 和底色几乎分不出来）
        .init(id: "blush", name: "粉白", me: 0xF3DDE4, ke: 0xFFFFFF),
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

    /// 128：QQ 那样实心，两边默认都是 100%
    static let defaultMeDensity = 1.0
    static let defaultKeDensity = 1.0
    /// 128：搬一次——127 存过的浓度回到 100%（她要的是 QQ 那种实心），127 默认那块淡粉换成 128 的粉
    static let solidMigrationKey = "app.bubble128.solid.migrated"
    static let oldDefaultMeHex: UInt32 = 0xF6E8EC

    static func migrateToSolid(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: solidMigrationKey) else { return }
        defaults.set(true, forKey: solidMigrationKey)
        for side in BubbleSide.allCases where defaults.object(forKey: densityKey(side)) != nil {
            defaults.set(1.0, forKey: densityKey(side))
        }
        if let stored = defaults.object(forKey: meColorKey) as? Int, UInt32(stored) == oldDefaultMeHex {
            defaults.set(Int(defaultHex(.me)), forKey: meColorKey)
        }
    }

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

/// 128：气泡上字的颜色。气泡（按浓度叠在底色上）够深就用白字，不然用平常的墨色——
/// 两种字各算一次和气泡的对比度（WCAG 的算法），哪个高用哪个。
enum BubbleInk {
    static let light: UInt32 = 0xFFFFFF
    /// 照片壁纸底下是什么颜色不知道，按一张偏暗的照片估
    static let photoBackdrop: UInt32 = 0x5A5A5A

    static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// 气泡颜色按浓度叠在底色上，屏幕上实际是这个颜色
    static func composite(_ fill: UInt32, density: Double, over backdrop: UInt32) -> UInt32 {
        let a = min(max(density.isFinite ? density : 1, 0), 1)
        func mix(_ shift: UInt32) -> UInt32 {
            let f = Double((fill >> shift) & 0xFF), b = Double((backdrop >> shift) & 0xFF)
            return UInt32((f * a + b * (1 - a)).rounded()) << shift
        }
        return mix(16) | mix(8) | mix(0)
    }

    /// true：这块气泡上用白字
    static func usesLightText(fill: UInt32, density: Double, backdrop: UInt32, darkInk: UInt32) -> Bool {
        let shown = composite(fill, density: density, over: backdrop)
        return contrast(light, shown) > contrast(darkInk, shown)
    }
}

extension Theme {
    /// 128：气泡一律是平的一块：白天和照片壁纸用她挑的颜色 × 浓度；夜里、卧室用夜色那两块（实心）
    private var bubbleUsesHerColors: Bool { !(skin == .night || isBedroom) }

    func bubbleFill(_ side: BubbleSide) -> Color {
        guard bubbleUsesHerColors else { return side == .me ? color.bubbleMe : color.bubbleKe }
        return Color(hex: bubbleHex(side))
    }

    func bubbleFillDensity(_ side: BubbleSide) -> Double {
        bubbleUsesHerColors ? bubbleDensity(side) : 1
    }

    /// 气泡上字的颜色：深气泡白字，浅气泡墨色
    func bubbleInk(_ side: BubbleSide) -> Color {
        guard bubbleUsesHerColors else { return side == .me ? color.bubbleMeText : color.bubbleKeText }
        let backdrop = lockscreenGlass ? BubbleInk.photoBackdrop : chatPalette.base
        let light = BubbleInk.usesLightText(
            fill: bubbleHex(side),
            density: bubbleDensity(side),
            backdrop: backdrop,
            darkInk: chatPalette.ink
        )
        return Color(hex: light ? BubbleInk.light : chatPalette.ink)
    }

    /// 照片壁纸上、气泡又很透的时候字还要那层字影；气泡够实就不要（实心块上的字影很脏）
    var bubbleTextNeedsShadow: Bool {
        lockscreenGlass && bubbleUsesHerColors && min(bubbleMeDensity, bubbleKeDensity) < 0.5
    }
}

/// 聊天里和设置预览里画气泡底的同一块。
/// 128：QQ 那样一整块平的圆角纯色：不描边、不加影子线、不加高光。浓度 < 100% 时透一点底色。
struct BubbleFill: View {
    let color: Color
    let density: Double
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color.opacity(reduceTransparency ? 1 : density))
            .allowsHitTesting(false)
    }
}
