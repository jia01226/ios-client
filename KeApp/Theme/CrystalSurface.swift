import SwiftUI

/// 已确认的山茶花晚霞背景。卧室模式仍由服务端信号覆盖。
struct AppAtmosphere: View {
    @EnvironmentObject private var theme: Theme

    var body: some View {
        ZStack {
            Image("CamelliaSunset")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            theme.effectiveBackground
                .opacity(theme.isBedroom ? 0.82 : 0.06)
                .ignoresSafeArea()
        }
        .accessibilityHidden(true)
    }
}
/// 玻璃不是实体粉色卡片：系统材质负责折射，令牌只控制薄薄的染色与边缘反光。
struct CrystalSurface: View {
    @EnvironmentObject private var theme: Theme
    let cornerRadius: CGFloat
    var strength: Double = 1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .opacity(min(1, theme.glass.materialBaseOpacity + strength * theme.glass.materialStrengthOpacity))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(theme.color.glassTint.opacity(theme.bubbleOpacity * strength))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                theme.color.glassEdge,
                                theme.color.accentSoft.opacity(theme.glass.accentEdgeOpacity),
                                theme.color.glassInnerLight
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: theme.metric.glassStrokeWidth
                    )
            }
            .shadow(
                color: theme.color.glassShadow,
                radius: theme.metric.glassShadowRadius,
                x: 0,
                y: theme.metric.glassShadowY
            )
    }
}
