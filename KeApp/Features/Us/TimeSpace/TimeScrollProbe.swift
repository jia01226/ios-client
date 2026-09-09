import SwiftUI
import UIKit

/// iOS 17 没有 ScrollGeometry API，通过同一个滚动视图的位置驱动月面。
struct TimeScrollProbe: UIViewRepresentable {
    @Binding var offset: CGFloat
    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.onScroll = { offset = max(0, $0) }
        return view
    }
    func updateUIView(_ view: ProbeView, context: Context) {
        view.onScroll = { offset = max(0, $0) }
        view.attach()
    }
    static func dismantleUIView(_ view: ProbeView, coordinator: ()) { view.stop() }

    final class ProbeView: UIView {
        var onScroll: ((CGFloat) -> Void)?
        private weak var scroll: UIScrollView?
        private var observation: NSKeyValueObservation?
        override func didMoveToWindow() { super.didMoveToWindow(); attach() }
        override func layoutSubviews() { super.layoutSubviews(); attach() }
        func attach() {
            var ancestor = superview
            while let candidate = ancestor {
                if let target = candidate as? UIScrollView {
                    guard scroll !== target else { return }
                    observation?.invalidate()
                    scroll = target
                    observation = target.observe(\.contentOffset, options: [.initial, .new]) { [weak self] target, _ in
                        let value = target.contentOffset.y + target.adjustedContentInset.top
                        DispatchQueue.main.async { [weak self, weak target] in
                            guard let self, let target, self.scroll === target else { return }
                            self.onScroll?(value)
                        }
                    }
                    return
                }
                ancestor = candidate.superview
            }
        }
        func stop() { observation?.invalidate(); observation = nil; scroll = nil; onScroll = nil }
    }
}
