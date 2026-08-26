import SwiftUI

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
