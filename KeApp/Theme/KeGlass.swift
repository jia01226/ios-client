import SwiftUI

/// 117：她要「玻璃质感」。用 iOS 26 系统自带的液态玻璃（会跟着底下的东西实时折射），
/// 再照小红书那篇「放生一块液态玻璃」的思路，左上、右下各压一道亮边，让玻璃有厚度。
/// 素笺页里选三档：纸感（不透明，跟以前一样）/ 轻玻璃（默认）/ 浮光（最透）。
/// 有字的地方（抽屉、卡片）纸色垫得厚一点，免得字看不清；系统开了「降低透明度」就一律回纸感。
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

struct KeGlass<S: InsettableShape>: View {
    let shape: S
    /// 有字的表面，纸色至少垫这么多
    var minPaper: Double = 0.35
    @AppStorage(KeGlassLevel.storageKey) private var levelValue = KeGlassLevel.light.rawValue
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var level: KeGlassLevel { KeGlassLevel(rawValue: levelValue) ?? .light }
    private var paper: Color { CamelliaPalette.resolve(savedPalette).paper }

    var body: some View {
        if reduceTransparency || level == .paper {
            shape.fill(paper)
        } else {
            let wash = max(minPaper, level == .float ? 0.12 : 0.4)
            ZStack {
                if #available(iOS 26.0, *) {
                    Color.clear.glassEffect(
                        (level == .float ? Glass.clear : Glass.regular).tint(paper.opacity(wash)),
                        in: shape
                    )
                } else {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(paper.opacity(min(1, wash + 0.25)))
                }
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

/// 素笺页里选玻璃那一排
struct KeGlassPicker: View {
    @AppStorage(KeGlassLevel.storageKey) private var levelValue = KeGlassLevel.light.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("玻璃质感").font(.system(size: 15, weight: .medium)).foregroundStyle(Ink.primary)
            HStack(spacing: 10) {
                ForEach(KeGlassLevel.allCases) { level in
                    let selected = levelValue == level.rawValue
                    Button { levelValue = level.rawValue } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(level.label).font(Ink.song(16)).foregroundStyle(Ink.primary)
                            Text(level.caption).font(.system(size: 11)).foregroundStyle(Ink.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                        .background { KeGlassPreview(level: level) }
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
            Text("作用在底部页签、设置抽屉、小本子的卡片和顶上的按钮上；字不会跟着变透。")
                .font(.system(size: 12)).foregroundStyle(Ink.secondary)
        }
    }
}

/// 选项卡片自己就用那一档画，选之前就看得到样子
private struct KeGlassPreview: View {
    let level: KeGlassLevel
    @AppStorage(CamelliaPalette.storageKey) private var savedPalette = CamelliaPalette.defaultPalette.rawValue

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let paper = CamelliaPalette.resolve(savedPalette).paper
        ZStack {
            LinearGradient(colors: [Ink.periodFill, paper, Ink.keFill], startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(shape)
            if level == .paper {
                shape.fill(paper)
            } else if #available(iOS 26.0, *) {
                Color.clear.glassEffect((level == .float ? Glass.clear : Glass.regular).tint(paper.opacity(level == .float ? 0.12 : 0.4)), in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(paper.opacity(level == .float ? 0.37 : 0.65))
            }
        }
    }
}
