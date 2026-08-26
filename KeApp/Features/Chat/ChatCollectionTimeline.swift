import ChatLayout
import SwiftUI
import UIKit

struct ChatTimelineItem: Identifiable, Equatable {
    let message: Message
    let isHighlighted: Bool
    let isThinkingExpanded: Bool
    let visibleSegmentCount: Int?

    var id: String { message.id }
}

struct ChatCollectionTimeline: UIViewControllerRepresentable {
    let items: [ChatTimelineItem]
    let streamRevision: Int
    let suppressAutoScrollUntil: Date
    let inputFocused: Bool
    let highlightedMessageID: String?
    let onThinkingToggle: (String) -> Void
    let onAttachmentTap: (ChatAttachment) -> Void
    let onBackgroundTap: () -> Void

    func makeUIViewController(context: Context) -> ChatCollectionTimelineController {
        ChatCollectionTimelineController(
            items: items,
            streamRevision: streamRevision,
            inputFocused: inputFocused,
            highlightedMessageID: highlightedMessageID,
            onThinkingToggle: onThinkingToggle,
            onAttachmentTap: onAttachmentTap,
            onBackgroundTap: onBackgroundTap
        )
    }

    func updateUIViewController(
        _ controller: ChatCollectionTimelineController,
        context: Context
    ) {
        controller.update(
            items: items,
            streamRevision: streamRevision,
            suppressAutoScrollUntil: suppressAutoScrollUntil,
            inputFocused: inputFocused,
            highlightedMessageID: highlightedMessageID,
            onThinkingToggle: onThinkingToggle,
            onAttachmentTap: onAttachmentTap,
            onBackgroundTap: onBackgroundTap
        )
    }
}

final class ChatCollectionTimelineController: UIViewController,
    UICollectionViewDataSource,
    ChatLayoutDelegate
{
    private enum PreservedEdge: Equatable {
        case top
        case bottom
    }

    private let chatLayout = CollectionViewChatLayout()
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: chatLayout
    )
    private var items: [ChatTimelineItem]
    private var streamRevision: Int
    private var inputFocused: Bool
    private var highlightedMessageID: String?
    private var onThinkingToggle: (String) -> Void
    private var onAttachmentTap: (ChatAttachment) -> Void
    private var onBackgroundTap: () -> Void
    private var didScrollToLatest = false
    private var lastTimelineHeight: CGFloat = 0

    init(
        items: [ChatTimelineItem],
        streamRevision: Int,
        inputFocused: Bool,
        highlightedMessageID: String?,
        onThinkingToggle: @escaping (String) -> Void,
        onAttachmentTap: @escaping (ChatAttachment) -> Void,
        onBackgroundTap: @escaping () -> Void
    ) {
        self.items = items
        self.streamRevision = streamRevision
        self.inputFocused = inputFocused
        self.highlightedMessageID = highlightedMessageID
        self.onThinkingToggle = onThinkingToggle
        self.onAttachmentTap = onAttachmentTap
        self.onBackgroundTap = onBackgroundTap
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let theme = Theme.shared
        chatLayout.delegate = self
        chatLayout.settings.interItemSpacing = theme.metric.gapM
        chatLayout.settings.additionalInsets = UIEdgeInsets(
            top: 0,
            left: theme.metric.pagePadding,
            bottom: theme.metric.gapL,
            right: theme.metric.pagePadding
        )
        chatLayout.keepContentOffsetAtBottomOnBatchUpdates = true
        chatLayout.keepContentAtBottomOfVisibleArea = true
        chatLayout.processOnlyVisibleItemsOnAnimatedBatchUpdates = false
        chatLayout.supportSelfSizingInvalidation = true

        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.selfSizingInvalidation = .enabled
        collectionView.isPrefetchingEnabled = false
        collectionView.dataSource = self
        collectionView.register(
            UICollectionViewCell.self,
            forCellWithReuseIdentifier: "ChatTimelineCell"
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(didTapTimeline))
        tap.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(tap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToLatestIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        let previousHeight = lastTimelineHeight
        let previousMaximumOffset = max(
            -collectionView.adjustedContentInset.top,
            collectionView.contentSize.height
                - previousHeight
                + collectionView.adjustedContentInset.bottom
        )
        let wasFollowingLatest = previousHeight > 0
            && collectionView.contentOffset.y >= previousMaximumOffset - 8

        super.viewDidLayoutSubviews()
        let currentHeight = collectionView.bounds.height
        lastTimelineHeight = currentHeight
        guard wasFollowingLatest,
              abs(currentHeight - previousHeight) > 0.5,
              !items.isEmpty else { return }

        chatLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
        scrollToLatest(animated: false)
    }

    func update(
        items newItems: [ChatTimelineItem],
        streamRevision newStreamRevision: Int,
        suppressAutoScrollUntil: Date,
        inputFocused newInputFocused: Bool,
        highlightedMessageID newHighlightedMessageID: String?,
        onThinkingToggle: @escaping (String) -> Void,
        onAttachmentTap: @escaping (ChatAttachment) -> Void,
        onBackgroundTap: @escaping () -> Void
    ) {
        self.onThinkingToggle = onThinkingToggle
        self.onAttachmentTap = onAttachmentTap
        self.onBackgroundTap = onBackgroundTap

        let oldItems = items
        let oldLastID = oldItems.last?.id
        let oldStreamRevision = streamRevision
        let oldInputFocused = inputFocused
        let oldHighlightedMessageID = highlightedMessageID
        items = newItems
        streamRevision = newStreamRevision
        inputFocused = newInputFocused
        highlightedMessageID = newHighlightedMessageID

        let mayAutoFollow = !newItems.contains(where: \.isThinkingExpanded)
            && Date.now >= suppressAutoScrollUntil
        let shouldFollowNewMessage = oldLastID != newItems.last?.id && mayAutoFollow
        let shouldFollowStream = oldStreamRevision != newStreamRevision && mayAutoFollow
        let shouldFollowKeyboard = !oldInputFocused && newInputFocused

        let hasStableIdentity = oldItems.map(\.id) == newItems.map(\.id)
        if hasStableIdentity {
            reloadChangedItems(from: oldItems, followLatest: shouldFollowNewMessage || shouldFollowStream)
        } else {
            let snapshot = chatLayout.getContentOffsetSnapshot(from: .bottom)
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
            if shouldFollowNewMessage {
                scrollToLatest(animated: true)
            } else if let snapshot {
                chatLayout.restoreContentOffset(with: snapshot)
            }
        }

        if shouldFollowKeyboard {
            scrollToLatest(animated: false)
        }
        if oldHighlightedMessageID != newHighlightedMessageID,
           let newHighlightedMessageID,
           let index = newItems.firstIndex(where: { $0.id == newHighlightedMessageID }) {
            collectionView.scrollToItem(
                at: IndexPath(item: index, section: 0),
                at: .centeredVertically,
                animated: true
            )
        }
    }

    private func reloadChangedItems(from oldItems: [ChatTimelineItem], followLatest: Bool) {
        let changedIndexes = items.indices.filter { oldItems[$0] != items[$0] }
        guard !changedIndexes.isEmpty else {
            if followLatest { scrollToLatest(animated: false) }
            return
        }

        let anchorIndex = changedIndexes.last { index in
            let old = oldItems[index]
            let new = items[index]
            return old.isThinkingExpanded != new.isThinkingExpanded
                || (new.isThinkingExpanded && old != new)
        }
        let preservedEdge: PreservedEdge? = anchorIndex.flatMap { index in
            let old = oldItems[index]
            let new = items[index]
            if !old.isThinkingExpanded && new.isThinkingExpanded { return .top }
            if old.isThinkingExpanded && !new.isThinkingExpanded { return .bottom }
            if old.isThinkingExpanded && new.isThinkingExpanded { return .top }
            return nil
        }
        let anchorIndexPath = anchorIndex.map { IndexPath(item: $0, section: 0) }
        let anchorY = anchorIndexPath.flatMap { indexPath in
            collectionView.layoutAttributesForItem(at: indexPath).flatMap { attributes in
                switch preservedEdge {
                case .top: return attributes.frame.minY - collectionView.contentOffset.y
                case .bottom: return attributes.frame.maxY - collectionView.contentOffset.y
                case nil: return nil
                }
            }
        }

        UIView.performWithoutAnimation {
            collectionView.performBatchUpdates {
                collectionView.reloadItems(
                    at: changedIndexes.map { IndexPath(item: $0, section: 0) }
                )
            } completion: { [weak self] _ in
                guard let self else { return }
                self.collectionView.layoutIfNeeded()
                if let anchorIndexPath, let anchorY, let preservedEdge,
                   let attributes = self.collectionView.layoutAttributesForItem(at: anchorIndexPath) {
                    let currentY: CGFloat = preservedEdge == .top
                        ? attributes.frame.minY - self.collectionView.contentOffset.y
                        : attributes.frame.maxY - self.collectionView.contentOffset.y
                    self.collectionView.contentOffset.y += currentY - anchorY
                } else if followLatest {
                    self.scrollToLatest(animated: false)
                }
            }
        }
    }

    private func scrollToLatestIfNeeded() {
        guard !didScrollToLatest, !items.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didScrollToLatest, !self.items.isEmpty else { return }
            self.collectionView.layoutIfNeeded()
            self.scrollToLatest(animated: false)
            self.didScrollToLatest = true
        }
    }

    private func scrollToLatest(animated: Bool) {
        guard !items.isEmpty else { return }
        collectionView.scrollToItem(
            at: IndexPath(item: items.count - 1, section: 0),
            at: .bottom,
            animated: animated
        )
    }

    @objc private func didTapTimeline() {
        onBackgroundTap()
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "ChatTimelineCell",
            for: indexPath
        )
        let item = items[indexPath.item]
        cell.backgroundColor = .clear
        cell.contentConfiguration = UIHostingConfiguration {
            MessageRow(
                message: item.message,
                isHighlighted: item.isHighlighted,
                isThinkingExpanded: item.isThinkingExpanded,
                visibleSegmentCount: item.visibleSegmentCount,
                onThinkingToggle: { [weak self] in
                    self?.onThinkingToggle(item.id)
                },
                onAttachmentTap: { [weak self] attachment in
                    self?.onAttachmentTap(attachment)
                }
            )
            .environmentObject(Theme.shared)
        }
        .margins(.all, 0)
        return cell
    }

    func initialLayoutAttributesForInsertedItem(
        _ chatLayout: CollectionViewChatLayout,
        of kind: ItemKind,
        at indexPath: IndexPath,
        modifying originalAttributes: ChatLayoutAttributes,
        on state: InitialAttributesRequestType
    ) {}

    func finalLayoutAttributesForDeletedItem(
        _ chatLayout: CollectionViewChatLayout,
        of kind: ItemKind,
        at indexPath: IndexPath,
        modifying originalAttributes: ChatLayoutAttributes
    ) {}
}
