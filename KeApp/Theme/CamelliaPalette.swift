import SwiftUI

/// Local appearance for the camellia page, independent of chat and day/night skins.
enum CamelliaPalette: String, CaseIterable, Identifiable {
    // 126：她认可的「三页同一张浅粉白纸」放第一个，没动过配色的人默认就是它。
    // 自己挑过别的（存进了 camellia.palette）照旧，不改她的选择。
    case blush, mist, white, ivory, cream

    static let storageKey = "camellia.palette"
    static let defaultPalette: CamelliaPalette = .blush
    static func resolve(_ value: String) -> CamelliaPalette {
        CamelliaPalette(rawValue: value) ?? defaultPalette
    }
    /// 126：页面里的 Ink（字色、强调色）跟着这里走；没存过就是默认的粉白。
    static func stored(in defaults: UserDefaults = .standard) -> CamelliaPalette {
        resolve(defaults.string(forKey: storageKey) ?? "")
    }
    /// 126：这台手机上她有没有自己挑过纸色（没挑过 = 跟着默认走，聊天也换成粉白）
    static func hasExplicitChoice(in defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: storageKey).flatMap(CamelliaPalette.init(rawValue:)) != nil
    }

    var id: String { rawValue }
    var label: String {
        switch self {
        case .blush: "粉白"
        case .mist: "浅雾蓝"
        case .white: "冷白"
        case .ivory: "暖白"
        case .cream: "浅米色"
        }
    }
    var paperRGB: (Double, Double, Double) {
        switch self {
        // 126：设计稿 blush.css 最后一层 --paper #FFFEFE，几乎是白、带一丝粉
        case .blush: (255 / 255, 254 / 255, 254 / 255)
        case .mist: (243 / 255, 248 / 255, 252 / 255)
        case .white: (250 / 255, 252 / 255, 253 / 255)
        // 121 她：「就 app 那个图标的背景色？暖色的白色」——取图标山茶底下那层米白
        case .ivory: (253 / 255, 252 / 255, 245 / 255)
        case .cream: (244 / 255, 239 / 255, 229 / 255)
        }
    }
    var paper: Color {
        let (r, g, b) = paperRGB
        return Color(red: r, green: g, blue: b)
    }
    var mistOpacity: Double {
        switch self {
        case .blush: 0.42
        case .mist: 0.60
        case .white: 0.56
        case .ivory: 0.46
        case .cream: 0.42
        }
    }
    var mistSaturation: Double { self == .mist ? 0.3 : 0 }
    /// 121：水纹去了色是一层灰，盖在暖白上就显冷（她说「我们」页冷了一点）。
    /// 暖的两款给水纹染一点米色，看起来是纸上的水痕，不是灰雾。
    var mistTint: Color {
        switch self {
        // 126：粉白纸上的水痕带一点点粉，不发灰也不发黄
        case .blush: Color(red: 1, green: 0.975, blue: 0.985)
        case .ivory: Color(red: 1, green: 0.965, blue: 0.9)
        case .cream: Color(red: 1, green: 0.95, blue: 0.88)
        case .mist, .white: .white
        }
    }
    /// 「我们」页的水纹在暖的两款上再淡一点，只动这一页，「柯的」那枝山茶不变
    var pondWash: Double { self == .ivory || self == .cream || self == .blush ? 0.7 : 0.9 }
    /// 126：粉白那款用设计稿的字色，别的四款还是原来的蓝墨
    static var ink: Color { stored().inks.primary }
    static var secondaryInk: Color { stored().inks.secondary }

    /// 126：每款纸配一套墨。页面只用 Ink.xxx，不直接拿这里的值。
    var inks: CamelliaInks { self == .blush ? .blush : .classic }
}

/// 126：「我们」「柯的」、小本子、设置抽屉共用的字色/强调色。
/// classic = 121 以来的蓝墨（tokens.json · day），blush = 2026-10-19 设计稿 blush.css 的最终值。
struct CamelliaInks {
    let primary: Color
    let secondary: Color
    let line: Color
    let accent: Color
    let periodFill: Color
    let track: Color
    let saving: Color
    /// 「柯的」山茶挂签上的竖排小字、标题
    let camelliaInk: Color
    let camelliaMuted: Color
    /// 底栏选中那一格垫的一层亮（玻璃上）
    let dockSelection: Color

    static let classic = CamelliaInks(
        primary: Color(hex: 0x3D5478), secondary: Color(hex: 0x5C6B7D), line: Color(hex: 0xA8B6BE),
        accent: Color(hex: 0x526D88), periodFill: Color(hex: 0xF5D7DF),
        track: Color(hex: 0xE4E9EE), saving: Color(hex: 0xB8788B),
        camelliaInk: Color(red: 0.24, green: 0.33, blue: 0.47), camelliaMuted: Color(red: 0.45, green: 0.52, blue: 0.62),
        dockSelection: Color.white.opacity(0.42)
    )
    static let blush = CamelliaInks(
        primary: Color(hex: 0x564653), secondary: Color(hex: 0x7A6572), line: Color(hex: 0xD8CDD3),
        // 经期那几天：设计稿最后一层是 #FAF0F4，放到手机屏上太浅，用同一套里的 #F8EBF0（--pink 第一层）
        accent: Color(hex: 0x8C617A), periodFill: Color(hex: 0xF8EBF0),
        track: Color(hex: 0xEEE5E9), saving: Color(hex: 0xB47792),
        camelliaInk: Color(hex: 0x564653), camelliaMuted: Color(hex: 0x7A6572),
        dockSelection: Color.white.opacity(0.42)
    )
}

/// Applied after compositing the stem and flowers, so their overlapping edges stay joined.
struct CamelliaSoftArtwork: ViewModifier {
    var scale: CGFloat = 1
    func body(content: Content) -> some View {
        content.compositingGroup()
            .saturation(0.67).contrast(0.91).brightness(0.015)
            .blur(radius: 0.16 * scale)
            .opacity(0.81)
    }
}
