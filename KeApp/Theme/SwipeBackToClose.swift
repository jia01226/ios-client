import SwiftUI

/// 102：她说「点开 App 任何一个界面，往右滑就退出去」。
/// 整屏盖上来的页面（小本子、日记、梦、星河、朋友圈、塔罗……）都加上：手指从左边缘往右划，页面跟着手走，
/// 划过 120 点或者甩得够快就退回去，不够就弹回来。只认左边缘起手，免得和星河转动、横向滑动打架。
/// 103：划走时底下露出全屏页的白底板、关掉时系统再播一遍收起动画，会白一下。底板改透明，关的时候不带动画。
/// 118：页面里面还盖着一层（日记点开的一篇、抽屉放大的小画）时，右划只收最上面那一层，外面的页面不动。
/// 里层用 `.swipeBackLayer { … }`：它会告诉外层「我还开着」，外层这时候不跟手。
struct SwipeBackToClose: ViewModifier {
    var action: () -> Void
    /// 整屏盖上来的那层要把底板改透明；页面里面再叠的一层不碰底板
    var presented = true
    @State private var offset: CGFloat = 0
    /// 里面还有一层开着
    @State private var covered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 左边缘多宽算起手：别的手势（星河转动之类）也照这个宽度让开
    static let edge: CGFloat = 44

    @ViewBuilder func body(content: Content) -> some View {
        if presented {
            swipeable(content).presentationBackground(.clear)
        } else {
            swipeable(content)
        }
    }

    private func swipeable(_ content: Content) -> some View {
        content
            .onPreferenceChange(SwipeBackCoveredKey.self) { covered = $0 }
            .offset(x: offset)
            .shadow(color: .black.opacity(offset > 0 ? 0.12 : 0), radius: 18, x: -6)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .global)
                    .onChanged { v in
                        guard !covered, v.startLocation.x < Self.edge, v.translation.width > 0,
                              abs(v.translation.width) > abs(v.translation.height) else { return }
                        offset = v.translation.width
                    }
                    .onEnded { v in
                        guard !covered, v.startLocation.x < Self.edge, offset > 0 else {
                            if offset != 0 { withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { offset = 0 } }
                            return
                        }
                        if offset > 120 || v.predictedEndTranslation.width > 320 {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { offset = 600 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.18)) {
                                var quiet = Transaction()
                                quiet.disablesAnimations = true
                                withTransaction(quiet) { action() }
                                // 里层收起后这个视图还在（外层页面），手要放回原位
                                if !presented { offset = 0 }
                            }
                        } else {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { offset = 0 }
                        }
                    }
            )
            .accessibilityAction(.escape) { if !covered { action() } }
            // 告诉更外面的那层：这里开着一层，先收我
            .preference(key: SwipeBackCoveredKey.self, value: true)
    }
}

/// 有没有可以右划收起的一层开着（只在同一个弹出层里往上传，sheet / fullScreenCover 各管各的）
struct SwipeBackCoveredKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    /// 整屏盖上来的页面（fullScreenCover 的内容）
    func swipeBackToClose(_ action: @escaping () -> Void) -> some View { modifier(SwipeBackToClose(action: action)) }
    /// 页面里面再叠的一层（不是系统弹出的）：右划先收这一层
    func swipeBackLayer(_ action: @escaping () -> Void) -> some View { modifier(SwipeBackToClose(action: action, presented: false)) }
}
