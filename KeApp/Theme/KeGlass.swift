import SwiftUI

/// 117：她要「玻璃质感」。用 iOS 26 系统自带的液态玻璃（会跟着底下的东西实时折射），
/// 再照小红书那篇「放生一块液态玻璃」的思路，左上、右下各压一道亮边，让玻璃有厚度。
/// 素笺页里选三档：纸感（不透明，跟以前一样）/ 轻玻璃（默认）/ 浮光（最透）。
/// 有字的地方（抽屉、卡片）纸色垫得厚一点，免得字看不清；系统开了「降低透明度」就一律回纸感。
/// 127：她说滑聊天又卡又晕。iOS 26 的液态玻璃浮在滚动的记录上，每一帧都要重新折射底下的内容，
/// 这里改成系统自带的 .ultraThinMaterial（UIKit 导航栏/底栏那种模糊，系统优化过）+ 一层纸色。
/// 三档还在，另加一条「玻璃透度」滑杆：透度 = 底下的东西透出来多少，纸色 = 1 − 透度（有字的表面不低于 minPaper）。
enum KeGlassLevel: Int, CaseIterable, Identifiable {
    case paper = 0, light = 1, float = 2
    static let storageKey = "ke.glass.level"
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .paper: "纸感"
        case .light: "轻玻璃"
        case .float: "浮光"
        }
    }
    var caption: String {
        switch self {
        case .paper: "不透，跟纸一样"
        case .light: "透一点，看得到底下"
        case .float: "最透，字少的地方最好看"
        }
    }
}

/// 127：「玻璃透度」0–1。三档只是把滑杆拨到固定位置。
enum KeGlassClarity {
    static let storageKey = "ke.glass.clarity"
    /// 默认照设计稿：浮栏薄薄一层纸色，底下的字看得到、糊开
    static let defaultValue = 0.75

    static func preset(_ level: KeGlassLevel) -> Double {
        switch level {
        case .paper: 0
        case .light: 0.55
        case .float: 0.85
        }
    }

    static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : defaultValue
    }

    /// 纸色垫多厚：1 − 透度，有字的表面不低于 minPaper
    static func paperOpacity(clarity: Double, minPaper: Double) -> Double {
        max(minPaper, 1 - clamp(clarity))
    }

    /// 以前在素笺里明确点过某一档的，换成那一档的透度；没点过的（一直用默认）走新默认。只搬一次。
    nonisolated static func migrate(_ defaults: UserDefaults) {
        guard defaults.object(forKey: storageKey) == nil else { return }
        guard let raw = defaults.object(forKey: KeGlassLevel.storageKey) as? Int,
              let level = KeGlassLevel(rawValue: raw) else { return }
        defaults.set(preset(level), forKey: storageKey)
    }
}

struct KeGlass<S: InsettableShape>: View {
    let shape: S
    /// 有字的表面，纸色至少垫这么多
    var minPaper: Double = 0.35
    @AppStorage(KeGlassClarity.storageKey) private var clarity = KeGlassClarity.defaultValue
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var paper: Color { CamelliaPalette.resolve(savedPalette).paper }

    var body: some View {
        KeGlassFill(shape: shape, paper: paper,
                    clarity: reduceTransparency ? 0 : KeGlassClarity.clamp(clarity), minPaper: minPaper)
    }
}

/// 真正画玻璃的那一块（素笺里的预览也用它）：一层系统模糊 + 纸色 + 左上右下两道亮边。
/// 透度为 0 就是实心纸，连模糊都不挂。
struct KeGlassFill<S: InsettableShape>: View {
    let shape: S
    let paper: Color
    let clarity: Double
    var minPaper: Double = 0.35

    var body: some View {
        if clarity <= 0.001 {
            shape.fill(paper)
        } else {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(paper.opacity(KeGlassClarity.paperOpacity(clarity: clarity, minPaper: minPaper)))
                // 左上亮、右下一点反光，中间几乎没有：像玻璃的厚度
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.8), location: 0),
                            .init(color: .white.opacity(0.1), location: 0.35),
                            .init(color: .white.opacity(0.0), location: 0.6),
                            .init(color: .white.opacity(0.4), location: 1),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
            }
        }
    }
}

/// 素笺页里选玻璃那一块：三档 + 一条「玻璃透度」滑杆 + 一块跟着变的预览
struct KeGlassPicker: View {
    @AppStorage(KeGlassClarity.storageKey) private var clarity = KeGlassClarity.defaultValue
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var paper: Color { CamelliaPalette.resolve(savedPalette).paper }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("玻璃质感").font(.system(size: 15, weight: .medium)).foregroundStyle(Ink.primary)
            HStack(spacing: 10) {
                ForEach(KeGlassLevel.allCases) { level in
                    let value = KeGlassClarity.preset(level)
                    let selected = abs(KeGlassClarity.clamp(clarity) - value) < 0.01
                    Button { clarity = value } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(level.label).font(Ink.song(16)).foregroundStyle(Ink.primary)
                            Text(level.caption).font(.system(size: 11)).foregroundStyle(Ink.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                        .background { KeGlassPreview(clarity: value, paper: paper) }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? Ink.accent : Ink.line.opacity(0.6), lineWidth: selected ? 1.6 : 0.8)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("玻璃质感：\(level.label)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            KeDrawerSlider(
                title: "玻璃透度",
                value: Binding(get: { KeGlassClarity.clamp(clarity) }, set: { clarity = KeGlassClarity.clamp($0) }),
                range: 0...1,
                valueText: "\(Int((KeGlassClarity.clamp(clarity) * 100).rounded()))%"
            )
            livePreview
            Text(reduceTransparency
                 ? "系统开了「降低透明度」，这些地方现在都是实心纸。"
                 : "作用在底部页签、聊天的顶栏和输入栏、设置抽屉、小本子的卡片上；字不会跟着变透。")
                .font(.system(size: 12)).foregroundStyle(Ink.secondary)
        }
    }

    /// 底下垫几行字，上面压一枚和聊天顶栏一样的胶囊：拖滑杆时看得到透出来多少
    private var livePreview: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("今天忙完了，终于能坐一会儿。")
                Text("那就靠着吧，我一直在听。")
                Text("晚上想吃什么？")
            }
            .font(.system(size: 13))
            .foregroundStyle(Ink.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            Text("柯")
                .font(Ink.song(16))
                .foregroundStyle(Ink.primary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background {
                    KeGlassFill(shape: Capsule(), paper: paper,
                                clarity: reduceTransparency ? 0 : KeGlassClarity.clamp(clarity), minPaper: 0.2)
                }
                .padding(.horizontal, 22)
        }
        .frame(height: 74)
        .background(
            LinearGradient(colors: [Ink.periodFill, paper, Ink.keFill], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("玻璃透度预览")
    }
}

/// 选项卡片自己就用那一档画，选之前就看得到样子
private struct KeGlassPreview: View {
    let clarity: Double
    let paper: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            LinearGradient(colors: [Ink.periodFill, paper, Ink.keFill], startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(shape)
            KeGlassFill(shape: shape, paper: paper, clarity: clarity, minPaper: 0)
        }
    }
}
