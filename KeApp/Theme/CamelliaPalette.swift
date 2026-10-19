import SwiftUI

/// Local appearance for the camellia page, independent of chat and day/night skins.
enum CamelliaPalette: String, CaseIterable, Identifiable {
    case mist, white, ivory, cream

    static let storageKey = "camellia.palette"
    static let defaultPalette: CamelliaPalette = .ivory
    static func resolve(_ value: String) -> CamelliaPalette {
        CamelliaPalette(rawValue: value) ?? defaultPalette
    }

    var id: String { rawValue }
    var label: String {
        switch self {
        case .mist: "浅雾蓝"
        case .white: "冷白"
        case .ivory: "暖白"
        case .cream: "浅米色"
        }
    }
    var paperRGB: (Double, Double, Double) {
        switch self {
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
        case .ivory: Color(red: 1, green: 0.965, blue: 0.9)
        case .cream: Color(red: 1, green: 0.95, blue: 0.88)
        case .mist, .white: .white
        }
    }
    /// 「我们」页的水纹在暖的两款上再淡一点，只动这一页，「柯的」那枝山茶不变
    var pondWash: Double { self == .ivory || self == .cream ? 0.7 : 0.9 }
    static let ink = Color(red: 0.24, green: 0.33, blue: 0.47)
    static let secondaryInk = Color(red: 0.36, green: 0.42, blue: 0.49)
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
