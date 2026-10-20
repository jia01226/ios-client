import SwiftUI
import UIKit

/// 底色随主题变化，卧室状态继续由服务端驱动。
/// 84：纯色底上的 Liquid Glass 看不出透，她觉得「不够玻璃」。在底色上铺几团很淡的月光和粉色光晕，
/// 玻璃才有东西可以透；卧室状态保持原来的纯色。
struct AppAtmosphere: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    // 85：她说「太平、没动效」，光晕曾经很慢地来回漂（一个来回 18 秒）。
    // 127：聊天记录就在这层上面滑，底下再漂会晕；浮栏的模糊也得跟着每帧重算。现在整层静止。

    var body: some View {
        ZStack {
            theme.effectiveBackground
            if !theme.isBedroom {
                let night = theme.skin == .night
                if !night && theme.chatPalette.atmosphereImage {
                    // 127：粉白那款铺设计稿那张淡粉底图（app-atmosphere：饱和度 0.4、轻糊、按 17% 正片叠底压在白纸上，
                    // 都提前烤进图里了），运行时就是一张静止的图，不挂滤镜、不混合。「降低透明度」时只留纸色。
                    if !reduceTransparency {
                        Color.clear
                            .overlay { Image("ChatAtmosphere").resizable().scaledToFill() }
                            .clipped()
                    }
                } else {
                    // 126：粉白纸几乎是白的，光晕只留一点影子（设计稿底图只有 10% 的淡）
                    let glow = night ? 1 : theme.chatPalette.glow
                    RadialGradient(
                        colors: [Color.white.opacity(night ? 0.14 : 0.70), .clear],
                        center: UnitPoint(x: 0.80, y: 0.10), startRadius: 0, endRadius: 280
                    )
                    RadialGradient(
                        colors: [theme.color.accentSoft.opacity((night ? 0.38 : 0.66) * glow), .clear],
                        center: UnitPoint(x: 0.10, y: 0.68), startRadius: 0, endRadius: 440
                    )
                    RadialGradient(
                        colors: [theme.sendColor.opacity((night ? 0.24 : 0.34) * glow), .clear],
                        center: UnitPoint(x: 0.94, y: 0.92), startRadius: 0, endRadius: 400
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 85：按下去轻轻一缩，松开弹回来。
struct PressBounceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// 玻璃不是实体粉色卡片：系统材质负责折射，令牌只控制薄薄的染色与边缘反光。
struct CrystalSurface: View {
    @EnvironmentObject private var theme: Theme
    let cornerRadius: CGFloat
    var strength: Double = 1
    var usesChatControls: Bool = false
    /// 127：放在聊天记录格子里的（工具状态卡）不挂实时模糊、不挂影子，只画一块静止的纸色 + 亮边
    var isStatic: Bool = false

    var body: some View {
        if isStatic {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.color.card.opacity(0.72))
                .overlay { rim }
        } else {
            liveBody
        }
    }

    private var rim: some View {
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

    private var liveBody: some View {
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
            .overlay { rim }
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
struct BackdropBlur: UIViewRepresentable {
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


struct FloatingGlassSurface: View {
    @EnvironmentObject private var theme: Theme
    let cornerRadius: CGFloat
    var lockscreen = false
    // 127：这些都浮在滚动的聊天记录上（照片壁纸时的提示条等），不用 iOS 26 液态玻璃，统一走系统模糊
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if lockscreen {
            shape.fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        } else {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(theme.color.accentSoft.opacity(0.04))
            }
        }
    }
}

/// Decorative day artwork is separate from the interactive 3D moon.
struct MoonJournalBackground: View {
    @EnvironmentObject private var theme: Theme
    var body: some View {
        theme.pageBackground.ignoresSafeArea()
    }
}

struct JournalMoonArtwork: View {
    @EnvironmentObject private var theme: Theme
    var body: some View {
        ZStack {
            Image("JournalMoon").resizable().scaledToFit().opacity(0.48)
            Ellipse().stroke(theme.pageAccent.opacity(0.45), lineWidth: 0.5)
                .frame(width: 220, height: 58).rotationEffect(.degrees(-22))
                .offset(x: -28, y: 24)
            Image(systemName: "sparkle").font(.system(size: 9, weight: .ultraLight))
                .foregroundStyle(theme.pageAccent).offset(x: -118, y: 8)
        }
        .opacity(theme.skin == .day ? 1 : 0)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct JournalBookCover: View {
    @EnvironmentObject private var theme: Theme
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(theme.pageAccent.opacity(0.48))
            RoundedRectangle(cornerRadius: 5).stroke(theme.pageAccent.opacity(0.65), lineWidth: 0.6).padding(3)
            Rectangle().fill(theme.pageColor.separator).frame(width: 1).padding(.leading, 8).frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                Image(systemName: "moon.fill").font(.system(size: 16, weight: .ultraLight))
                Text("MOONLIGHT\nJOURNAL").font(.custom("Didot", size: 7)).tracking(1.1).multilineTextAlignment(.center)
            }.foregroundStyle(theme.pageColor.textPrimary.opacity(0.55))
        }.frame(width: 74, height: 100)
    }
}

struct MoonOrbitGuide: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY))
            path.addCurve(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.maxY),
                          control1: CGPoint(x: rect.maxX, y: rect.height * 0.3),
                          control2: CGPoint(x: rect.minX, y: rect.height * 0.7))
        }
    }
}
