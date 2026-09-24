import SwiftUI

// MARK: - 玩页风铃（2026-09-23）
//
// 风铃是她画的水彩原图，从那张三串的整图上切下来的。
// 每串切成两截：
//   Head —— 金环 + 一小段线；
//   Body —— 第一颗金珠往下的全部。
// 中间那段线用一条金色细线接上，长度可调。
//
// 为什么要切开：环得钉死在枝上，玉坠该落在哪儿是另一回事。
// 一整张图的话，环一挪玉坠就跟着跑，怎么都对不上枝。
//
// ⚠️ 挂住的观感靠层序：风铃画在花枝【下面】，枝压住金环的上半截，
//    看着才是穿过去挂着的。别把这两层调过来。


// MARK: - 叠在玉坠上的图案
//
// 原图那颗玉坠上画的是塔罗牌。塔罗入口 0923 搬到了聊天页顶上，
// 这颗珠子改成共读，牌面就从图里抹掉了（抹之前的原图存在
// Design/play-chime-0923/ChimeLeftBody-原带塔罗牌.png），换这本摊开的书上去。
// 金色和线宽都照原图里其它图案取的样。

enum ChimeGlyphKind {
    case openBook

    @ViewBuilder
    func view(width: CGFloat, color: Color) -> some View {
        switch self {
        case .openBook: OpenBookGlyph(color: color).frame(width: width, height: width * 0.80)
        }
    }
}

struct OpenBookGlyph: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lw = max(1.1, w * 0.040)

            ZStack {
                // 摊开的两页
                Path { p in
                    p.move(to: CGPoint(x: w * 0.50, y: h * 0.20))
                    p.addQuadCurve(to: CGPoint(x: w * 0.05, y: h * 0.12),
                                   control: CGPoint(x: w * 0.27, y: h * 0.03))
                    p.addLine(to: CGPoint(x: w * 0.05, y: h * 0.80))
                    p.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.90),
                                   control: CGPoint(x: w * 0.27, y: h * 0.84))
                    p.addQuadCurve(to: CGPoint(x: w * 0.95, y: h * 0.80),
                                   control: CGPoint(x: w * 0.73, y: h * 0.84))
                    p.addLine(to: CGPoint(x: w * 0.95, y: h * 0.12))
                    p.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.20),
                                   control: CGPoint(x: w * 0.73, y: h * 0.03))
                    p.closeSubpath()
                }
                .stroke(color, style: StrokeStyle(lineWidth: lw, lineJoin: .round))

                // 书脊
                Path { p in
                    p.move(to: CGPoint(x: w * 0.50, y: h * 0.20))
                    p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.90))
                }
                .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))

                // 两页上各两道字
                ForEach([0.42, 0.58], id: \.self) { row in
                    Path { p in
                        p.move(to: CGPoint(x: w * 0.14, y: h * row))
                        p.addLine(to: CGPoint(x: w * 0.40, y: h * (row + 0.03)))
                        p.move(to: CGPoint(x: w * 0.60, y: h * (row + 0.03)))
                        p.addLine(to: CGPoint(x: w * 0.86, y: h * row))
                    }
                    .stroke(color.opacity(0.75), style: StrokeStyle(lineWidth: lw * 0.72, lineCap: .round))
                }
            }
        }
    }
}

struct ChimeBeadSpec {
    let title: String
    let identifier: String
    let action: () -> Void
}

struct ChimeStrand: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let headAsset: String
    let bodyAsset: String
    let sourceWidth: CGFloat     // 切图的原始宽，用来换算显示比例
    let displayWidth: CGFloat
    let headSourceHeight: CGFloat
    let bodySourceHeight: CGFloat
    let ringCenterInHead: CGFloat   // 金环中心在 Head 里的 y（原始像素）
    let cordOffsetX: CGFloat        // 接线要对准金环，环不一定在正中
    let cordExtra: CGFloat          // 接在中间的那段线有多长

    let topBeadY: CGFloat        // 上玉坠中心在 Body 里的相对高度
    let bottomBeadY: CGFloat
    let beadW: CGFloat
    let beadH: CGFloat

    let topGlyph: ChimeGlyphKind?   // 原图那颗图案被抹掉时，叠一个新的上去
    let top: ChimeBeadSpec
    let bottom: ChimeBeadSpec
    let label: String
    let period: Double
    let phase: Double

    private var scale: CGFloat { displayWidth / sourceWidth }
    private var headHeight: CGFloat { headSourceHeight * scale }
    private var bodyHeight: CGFloat { bodySourceHeight * scale }
    private var totalHeight: CGFloat { headHeight + cordExtra + bodyHeight }
    /// 摆动的轴就在金环上。
    private var ringAnchor: UnitPoint { UnitPoint(x: 0.5 + cordOffsetX / displayWidth, y: ringCenterInHead * scale / totalHeight) }

    // 接线的金色，取自原图那根线；图案的金色取自原图玉坠上的线描。
    private let cordGold = Color(hex: 0xD3A04A)
    private let glyphGold = Color(hex: 0xB8721F)

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let swing = reduceMotion ? 0 : sin(t * .pi * 2 / period + phase) * 1.7

                VStack(spacing: 0) {
                    Image(headAsset)
                        .resizable()
                        .frame(width: displayWidth, height: headHeight)

                    Rectangle()
                        .fill(cordGold)
                        .frame(width: 1.8, height: cordExtra)
                        .offset(x: cordOffsetX)

                    Image(bodyAsset)
                        .resizable()
                        .frame(width: displayWidth, height: bodyHeight)
                        .overlay(alignment: .topLeading) {
                            if let topGlyph {
                                topGlyph.view(width: displayWidth * 0.46, color: glyphGold)
                                    .position(x: displayWidth / 2, y: bodyHeight * topBeadY)
                            }
                        }
                        .overlay(hotspot(top, centerY: topBeadY))
                        .overlay(hotspot(bottom, centerY: bottomBeadY))
                }
                .rotationEffect(.degrees(swing), anchor: ringAnchor)
            }

            // 名字不跟着摆，晃着读着累。
            Text(label)
                .font(.custom("NotoSerifSC-Regular", size: 16, relativeTo: .body).weight(.light))
                .foregroundStyle(theme.color.textPrimary.opacity(0.88))
        }
    }

    /// 叠在玉坠上的透明热区。
    private func hotspot(_ spec: ChimeBeadSpec, centerY: CGFloat) -> some View {
        Button(action: spec.action) {
            Color.clear
                .frame(width: displayWidth * beadW, height: bodyHeight * beadH)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spec.title)
        .accessibilityIdentifier(spec.identifier)
        .position(x: displayWidth / 2, y: bodyHeight * centerY)
    }
}
