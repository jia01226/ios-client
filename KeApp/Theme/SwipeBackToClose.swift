import SwiftUI

/// 102：她说「点开 App 任何一个界面，往右滑就退出去」。
/// 整屏盖上来的页面（小本子、日记、梦、星河、朋友圈、塔罗……）都加上：手指从左边缘往右划，页面跟着手走，
/// 划过 120 点或者甩得够快就退回去，不够就弹回来。只认左边缘起手，免得和星河转动、横向滑动打架。
/// 103：划走时底下露出全屏页的白底板、关掉时系统再播一遍收起动画，会白一下。底板改透明，关的时候不带动画。
struct SwipeBackToClose: ViewModifier {
    var action: () -> Void
    @State private var offset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let edge: CGFloat = 44

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .shadow(color: .black.opacity(offset > 0 ? 0.12 : 0), radius: 18, x: -6)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .global)
                    .onChanged { v in
                        guard v.startLocation.x < Self.edge, v.translation.width > 0,
                              abs(v.translation.width) > abs(v.translation.height) else { return }
                        offset = v.translation.width
                    }
                    .onEnded { v in
                        guard v.startLocation.x < Self.edge, offset > 0 else { offset = 0; return }
                        if offset > 120 || v.predictedEndTranslation.width > 320 {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { offset = 600 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.18)) {
                                var quiet = Transaction()
                                quiet.disablesAnimations = true
                                withTransaction(quiet) { action() }
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { offset = 0 }
                        }
                    }
            )
            .accessibilityAction(.escape, action)
            .presentationBackground(.clear)
    }
}

extension View {
    func swipeBackToClose(_ action: @escaping () -> Void) -> some View { modifier(SwipeBackToClose(action: action)) }
}
