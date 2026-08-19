import SwiftUI
import UIKit

/// 已确认的山茶花晚霞背景。卧室模式仍由服务端信号覆盖。
struct AppAtmosphere: View {
    @EnvironmentObject private var theme: Theme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("CamelliaSunset")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                theme.effectiveBackground
                    .opacity(theme.isBedroom ? 0.82 : 0.06)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
/// 玻璃不是实体粉色卡片：系统材质负责折射，令牌只控制薄薄的染色与边缘反光。
struct CrystalSurface: View {
    @EnvironmentObject private var theme: Theme
    let cornerRadius: CGFloat
    var strength: Double = 1
    var usesChatControls: Bool = false

    var body: some View {
        ZStack {
            BackdropBlur(
                intensity: usesChatControls
                    ? theme.glassBlur / theme.glass.maximumBlurValue
                    : theme.glass.fixedSurfaceBlurIntensity,
                dark: theme.skin == .night || theme.isBedroom
            )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.color.glassTint.opacity(surfaceTintOpacity))
        }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

    private var surfaceTintOpacity: Double {
        if usesChatControls {
            return min(1, theme.bubbleOpacity * strength)
        }
        return min(1, theme.glass.fixedSurfaceTintOpacity * strength)
    }
}

/// 用公开的 UIVisualEffectView + 可暂停动画器，把系统材质强度变成连续可调值。
/// Slider 的每一次变化都会直接更新 fractionComplete，不是只改旁边的数字。
private struct BackdropBlur: UIViewRepresentable {
    let intensity: Double
    let dark: Bool

    final class Coordinator {
        var animator: UIViewPropertyAnimator?
        var styleRawValue: Int?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: nil)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        let style: UIBlurEffect.Style = dark
            ? .systemUltraThinMaterialDark
            : .systemUltraThinMaterialLight

#if DEBUG
        // UIVisualEffectView 的暂停动画器会让 XCUITest 把每次点击误判成
        // “仍在动画”，固定空等约一分钟。测试只需要静态材质；聊天本身的
        // 键盘、滚动和折叠动画仍保持开启，真机路径完全不受影响。
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-ui-test-") }) {
            context.coordinator.animator?.stopAnimation(true)
            context.coordinator.animator = nil
            context.coordinator.styleRawValue = style.rawValue
            view.effect = UIBlurEffect(style: style)
            return
        }
#endif

        if context.coordinator.animator == nil
            || context.coordinator.styleRawValue != style.rawValue {
            context.coordinator.animator?.stopAnimation(true)
            view.effect = nil

            let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak view] in
                view?.effect = UIBlurEffect(style: style)
            }
            animator.pausesOnCompletion = true
            context.coordinator.animator = animator
            context.coordinator.styleRawValue = style.rawValue
        }

        context.coordinator.animator?.fractionComplete = min(max(intensity, 0), 1)
    }

    static func dismantleUIView(_ view: UIVisualEffectView, coordinator: Coordinator) {
        coordinator.animator?.stopAnimation(true)
        view.effect = nil
    }
}
