import SwiftUI
import UIKit

@MainActor
final class ChatScrollAnchorController: ObservableObject {
    enum AnchorEdge: Equatable {
        case top
        case viewport
    }

    private final class WeakAnchor {
        weak var view: UIView?

        init(_ view: UIView) {
            self.view = view
        }
    }

    private struct PendingRestore {
        let token: UUID
        let messageID: String
        let edge: AnchorEdge
        let viewportCoordinate: CGFloat
        var attempts: Int
    }

    private weak var scrollView: UIScrollView?
    private var anchors: [String: WeakAnchor] = [:]
    private var pendingRestore: PendingRestore?
    private var scheduledToken: UUID?
    private var keyboardDisplayLink: CADisplayLink?
    private var keyboardFollowDeadline: CFTimeInterval = 0

    func register(_ anchor: UIView, messageID: String) {
        anchors[messageID] = WeakAnchor(anchor)
        resolveScrollView(from: anchor)
        if pendingRestore?.messageID == messageID {
            scheduleRestore(messageID: messageID)
        }
    }

    func prepareToRestore(messageID: String, edge: AnchorEdge) {
        cancelPreservation()
        guard
            let anchor = anchors[messageID]?.view,
            anchor.window != nil
        else { return }

        resolveScrollView(from: anchor)
        guard let scrollView else { return }
        let boundsInViewport = anchor.convert(anchor.bounds, to: nil)
        pendingRestore = PendingRestore(
            token: UUID(),
            messageID: messageID,
            edge: edge,
            viewportCoordinate: edge == .top
                ? boundsInViewport.minY
                : scrollView.contentOffset.y,
            attempts: 0
        )
    }

    func restoreAfterCurrentLayout(messageID: String) {
        guard pendingRestore?.messageID == messageID else { return }
        scheduleRestore(messageID: messageID)
    }

    func anchorDidLayout(messageID: String) {
        guard pendingRestore?.messageID == messageID else { return }
        scheduleRestore(messageID: messageID)
    }

    func cancelPreservation() {
        pendingRestore = nil
        scheduledToken = nil
    }

    func followBottomAlongsideKeyboard(duration: TimeInterval) {
        cancelPreservation()
        if scrollView == nil,
           let mountedAnchor = anchors.values
               .compactMap(\.view)
               .first(where: { $0.window != nil }) {
            // 首次 register 可能发生在 UIView 还没挂进 SwiftUI 层级时；
            // 键盘不触发消息重建，所以要在真正使用前从已挂载探针再解析一次。
            resolveScrollView(from: mountedAnchor)
        }
        keyboardFollowDeadline = max(
            keyboardFollowDeadline,
            CACurrentMediaTime() + max(duration, 0.1) + 0.1
        )
        pinToBottom()
        guard keyboardDisplayLink == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(followKeyboardFrame))
        displayLink.add(to: .main, forMode: .common)
        keyboardDisplayLink = displayLink
    }

    func stopFollowingBottom() {
        keyboardDisplayLink?.invalidate()
        keyboardDisplayLink = nil
        keyboardFollowDeadline = 0
    }

    @objc private func followKeyboardFrame(_ displayLink: CADisplayLink) {
        pinToBottom()
        if displayLink.timestamp >= keyboardFollowDeadline {
            stopFollowingBottom()
        }
    }

    private func pinToBottom() {
        guard let scrollView else { return }
        scrollView.layoutIfNeeded()
        let minimumY = -scrollView.adjustedContentInset.top
        let maximumY = max(
            minimumY,
            scrollView.contentSize.height
                + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height
        )
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: maximumY),
            animated: false
        )
    }

    private func scheduleRestore(messageID: String) {
        guard let pendingRestore, pendingRestore.messageID == messageID else { return }
        let token = pendingRestore.token
        guard scheduledToken != token else { return }
        scheduledToken = token
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.scheduledToken == token else { return }
            self.scheduledToken = nil
            self.restoreOnce(token: token)
        }
    }

    private func restoreOnce(token: UUID) {
        guard
            var pendingRestore,
            pendingRestore.token == token,
            let anchor = anchors[pendingRestore.messageID]?.view,
            let scrollView,
            anchor.window != nil,
            !scrollView.isTracking,
            !scrollView.isDragging,
            !scrollView.isDecelerating
        else {
            if self.pendingRestore?.token == token {
                cancelPreservation()
            }
            return
        }

        scrollView.layoutIfNeeded()
        let boundsInViewport = anchor.convert(anchor.bounds, to: nil)
        let currentCoordinate = pendingRestore.edge == .top
            ? boundsInViewport.minY
            : scrollView.contentOffset.y
        let delta = currentCoordinate - pendingRestore.viewportCoordinate
        guard abs(delta) > 0.5 else {
            pendingRestore.attempts += 1
            self.pendingRestore = pendingRestore
            if pendingRestore.attempts >= 3 {
                cancelPreservation()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                    guard self?.pendingRestore?.token == token else { return }
                    self?.scheduleRestore(messageID: pendingRestore.messageID)
                }
            }
            return
        }

        let minimumY = -scrollView.adjustedContentInset.top
        let maximumY = max(
            minimumY,
            scrollView.contentSize.height
                + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height
        )
        let proposedY = pendingRestore.edge == .top
            ? scrollView.contentOffset.y + delta
            : pendingRestore.viewportCoordinate
        let targetY = min(maximumY, max(minimumY, proposedY))
        cancelPreservation()
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: targetY),
            animated: false
        )
    }

    private func resolveScrollView(from anchor: UIView) {
        var ancestor = anchor.superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView {
                self.scrollView = scrollView
                return
            }
            ancestor = view.superview
        }
    }
}

final class ChatMessageAnchorView: UIView {
    weak var controller: ChatScrollAnchorController?
    var messageID = ""

    override func layoutSubviews() {
        super.layoutSubviews()
        controller?.anchorDidLayout(messageID: messageID)
    }
}

struct ChatMessageAnchorProbe: UIViewRepresentable {
    let messageID: String
    let controller: ChatScrollAnchorController

    func makeUIView(context: Context) -> ChatMessageAnchorView {
        let view = ChatMessageAnchorView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.controller = controller
        view.messageID = messageID
        controller.register(view, messageID: messageID)
        return view
    }

    func updateUIView(_ uiView: ChatMessageAnchorView, context: Context) {
        uiView.controller = controller
        uiView.messageID = messageID
        controller.register(uiView, messageID: messageID)
    }
}

struct MessageUnitLayout: Layout {
    let includesThinking: Bool
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let bubble = subviews.last else { return .zero }
        let bubbleSize = bubble.sizeThatFits(
            ProposedViewSize(width: proposal.width, height: nil)
        )
        guard includesThinking, subviews.count > 1 else { return bubbleSize }

        let thinkingSize = subviews[0].sizeThatFits(
            ProposedViewSize(width: proposal.width, height: nil)
        )
        return CGSize(
            width: max(thinkingSize.width, bubbleSize.width),
            height: thinkingSize.height + spacing + bubbleSize.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let bubble = subviews.last else { return }
        var nextY = bounds.minY

        if includesThinking, subviews.count > 1 {
            let thinkingProposal = ProposedViewSize(width: bounds.width, height: nil)
            let thinkingSize = subviews[0].sizeThatFits(thinkingProposal)
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: nextY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: thinkingSize.height)
            )
            nextY += thinkingSize.height + spacing
        }

        let bubbleProposal = ProposedViewSize(width: bounds.width, height: nil)
        let bubbleSize = bubble.sizeThatFits(bubbleProposal)
        bubble.place(
            at: CGPoint(x: bounds.minX, y: nextY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bubbleSize.height)
        )
    }
}
