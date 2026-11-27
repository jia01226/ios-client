import SwiftUI
import UIKit

/// 11-27 她看了 Vera 的「翻书」（querencia-motion），想让柯的日记也能一页一页翻。
/// 108 她说过「点开不要翻页动画」：点开一篇照旧直接打开；翻开以后左右划才是翻书——往左划翻到更早的一篇，往右划翻回来。
/// 用系统的 UIPageViewController 卷页（pageCurl）：纸跟着手指卷起来、背面透一点字，跟 Vera 那本书一个意思，
/// 但是原生的，不用 WebGL，不费电。左边缘 44 点留给 swipeBackLayer（右划回目录），卷页不从那里起手。
struct DiaryBook<Page: View>: UIViewControllerRepresentable {
    /// 目录里现在显示的那些（新的在前）：翻下一页 = 更早的一篇
    let entries: [RemoteDiary]
    /// 正在看的那一篇（同一天另一篇的按钮会改它，书跟着翻过去）
    let currentID: Int
    let paper: Color
    var onTurn: (RemoteDiary) -> Void
    @ViewBuilder var page: (RemoteDiary) -> Page

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let book = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
                                        options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue])
        book.dataSource = context.coordinator
        book.delegate = context.coordinator
        book.view.backgroundColor = UIColor(paper)
        // 卷页自带的「点左右边就翻」会抢「目录」和「同一天的另一篇」这些按钮，只留划的
        for gesture in book.gestureRecognizers {
            if gesture is UITapGestureRecognizer { gesture.isEnabled = false }
            gesture.delegate = context.coordinator
        }
        if let first = context.coordinator.controller(for: currentID) {
            book.setViewControllers([first], direction: .forward, animated: false)
            context.coordinator.shownID = currentID
        }
        return book
    }

    func updateUIViewController(_ book: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        let shownBefore = coordinator.shownID
        coordinator.parent = self
        guard currentID != shownBefore, let next = coordinator.controller(for: currentID) else { return }
        // 外面换了一篇（点了同一天的另一篇）：照目录顺序往前或往后卷过去
        let forward = (coordinator.index(of: currentID) ?? 0) > (shownBefore.flatMap(coordinator.index(of:)) ?? 0)
        book.setViewControllers([next], direction: forward ? .forward : .reverse, animated: true)
        coordinator.shownID = currentID
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: DiaryBook
        /// 书上现在摊着的那一篇
        var shownID: Int?

        init(_ parent: DiaryBook) { self.parent = parent }

        func index(of id: Int) -> Int? { parent.entries.firstIndex { $0.id == id } }

        func controller(for id: Int) -> UIViewController? {
            guard let entry = parent.entries.first(where: { $0.id == id }) else { return nil }
            return DiaryLeaf(entry: entry, root: AnyView(parent.page(entry)), paper: UIColor(parent.paper))
        }

        private func neighbour(of vc: UIViewController, step: Int) -> UIViewController? {
            guard let leaf = vc as? DiaryLeaf, let i = index(of: leaf.entry.id) else { return nil }
            let j = i + step
            guard parent.entries.indices.contains(j) else { return nil }
            let entry = parent.entries[j]
            return DiaryLeaf(entry: entry, root: AnyView(parent.page(entry)), paper: UIColor(parent.paper))
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
            neighbour(of: vc, step: -1)
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
            neighbour(of: vc, step: 1)
        }

        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let leaf = pvc.viewControllers?.first as? DiaryLeaf else { return }
            shownID = leaf.entry.id
            parent.onTurn(leaf.entry)
        }

        /// 左边缘留给「右划回目录」
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let view = gesture.view else { return true }
            return gesture.location(in: view).x > SwipeBackToClose.edge
        }
    }
}

/// 书里的一页：纸色底，靠书脊那边一道淡淡的阴影，像装订进去的纸
private final class DiaryLeaf: UIHostingController<AnyView> {
    let entry: RemoteDiary

    init(entry: RemoteDiary, root: AnyView, paper: UIColor) {
        self.entry = entry
        super.init(rootView: AnyView(
            root.overlay(alignment: .leading) {
                LinearGradient(colors: [.black.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 18)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        ))
        view.backgroundColor = paper
    }

    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
