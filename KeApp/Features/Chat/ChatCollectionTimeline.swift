import ChatLayout
import SwiftUI
import UIKit

enum ChatTimelineItemKind: Equatable {
    case thinking
    case message
}

struct ChatTimelineItem: Identifiable, Equatable {
    let kind: ChatTimelineItemKind
    let message: Message
    let isHighlighted: Bool
    let visibleSegmentCount: Int?

    var id: String {
        "\(message.id)::\(kind == .thinking ? "thinking" : "message")"
    }

    var messageID: String { message.id }

    static func make(
        message: Message,
        isHighlighted: Bool,
        visibleSegmentCount: Int?
    ) -> [Self] {
        var result: [Self] = []
        if message.sender == .ke, hasThinking(message) {
            result.append(Self(
                kind: .thinking,
                message: message,
                isHighlighted: false,
                visibleSegmentCount: nil
            ))
        }
        result.append(Self(
            kind: .message,
            message: message,
            isHighlighted: isHighlighted,
            visibleSegmentCount: visibleSegmentCount
        ))
        return result
    }

    private static func hasThinking(_ message: Message) -> Bool {
        [message.thoughtSummary, message.thoughtNote].contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

struct ChatCollectionTimeline: UIViewControllerRepresentable {
    let items: [ChatTimelineItem]
    let streamRevision: Int
    let suppressAutoScrollUntil: Date
    let inputFocused: Bool
    let highlightedMessageID: String?
    let onThinkingOpen: (String) -> Void
    let onAttachmentTap: (ChatAttachment) -> Void
    let onBackgroundTap: () -> Void

    func makeUIViewController(context: Context) -> ChatCollectionTimelineController {
        ChatCollectionTimelineController(
            items: items,
            streamRevision: streamRevision,
            inputFocused: inputFocused,
            highlightedMessageID: highlightedMessageID,
            onThinkingOpen: onThinkingOpen,
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
            onThinkingOpen: onThinkingOpen,
            onAttachmentTap: onAttachmentTap,
            onBackgroundTap: onBackgroundTap
        )
    }
}

final class ChatCollectionTimelineController: UIViewController,
    UICollectionViewDataSource,
    ChatLayoutDelegate
{
    private let chatLayout = CollectionViewChatLayout()
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: chatLayout
    )
    private var items: [ChatTimelineItem]
    private var streamRevision: Int
    private var inputFocused: Bool
    private var highlightedMessageID: String?
    private var onThinkingOpen: (String) -> Void
    private var onAttachmentTap: (ChatAttachment) -> Void
    private var onBackgroundTap: () -> Void
    private var didScrollToLatest = false
    private var lastTimelineHeight: CGFloat = 0

    init(
        items: [ChatTimelineItem],
        streamRevision: Int,
        inputFocused: Bool,
        highlightedMessageID: String?,
        onThinkingOpen: @escaping (String) -> Void,
        onAttachmentTap: @escaping (ChatAttachment) -> Void,
        onBackgroundTap: @escaping () -> Void
    ) {
        self.items = items
        self.streamRevision = streamRevision
        self.inputFocused = inputFocused
        self.highlightedMessageID = highlightedMessageID
        self.onThinkingOpen = onThinkingOpen
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
        collectionView.accessibilityIdentifier = "chat-timeline"
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
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
        onThinkingOpen: @escaping (String) -> Void,
        onAttachmentTap: @escaping (ChatAttachment) -> Void,
        onBackgroundTap: @escaping () -> Void
    ) {
        self.onThinkingOpen = onThinkingOpen
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

        let mayAutoFollow = Date.now >= suppressAutoScrollUntil
        let shouldFollowNewMessage = oldLastID != newItems.last?.id && mayAutoFollow
        let shouldFollowStream = oldStreamRevision != newStreamRevision && mayAutoFollow
        let shouldFollowLatest = shouldFollowNewMessage || shouldFollowStream
        let shouldFollowKeyboard = !oldInputFocused && newInputFocused

        let hasStableIdentity = oldItems.map(\.id) == newItems.map(\.id)
        if hasStableIdentity {
            reloadChangedItems(from: oldItems, followLatest: shouldFollowLatest)
        } else {
            let snapshot = shouldFollowLatest
                ? nil
                : chatLayout.getContentOffsetSnapshot(from: .top)
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
            if shouldFollowLatest {
                scrollToLatest(animated: true)
            } else if let snapshot {
                chatLayout.restoreContentOffset(with: snapshot)
            }
        }

        if shouldFollowKeyboard {
            followLatestAfterKeyboardLayout()
        }
        if oldHighlightedMessageID != newHighlightedMessageID,
           let newHighlightedMessageID,
           let index = newItems.firstIndex(where: {
               $0.messageID == newHighlightedMessageID && $0.kind == .message
           }) {
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

        let positionSnapshot = followLatest
            ? nil
            : chatLayout.getContentOffsetSnapshot(from: .top)

        UIView.performWithoutAnimation {
            collectionView.performBatchUpdates {
                collectionView.reloadItems(
                    at: changedIndexes.map { IndexPath(item: $0, section: 0) }
                )
            } completion: { [weak self] _ in
                guard let self else { return }
                self.collectionView.layoutIfNeeded()
                if let positionSnapshot {
                    self.chatLayout.restoreContentOffset(with: positionSnapshot)
                } else if followLatest {
                    self.scrollToLatest(animated: false)
                }
            }
        }
    }

    private func followLatestAfterKeyboardLayout() {
        scrollToLatest(animated: false)
        for delay in [0.05, 0.25, 0.45] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.chatLayout.invalidateLayout()
                self.collectionView.layoutIfNeeded()
                self.scrollToLatest(animated: false)
            }
        }
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
            as? CGRect,
              endFrame.minY < UIScreen.main.bounds.maxY else { return }
        // UIKit 通知比 SwiftUI FocusState 稳定：即使用户从历史位置点输入框，
        // 也要等系统确定键盘终点后，把最新消息带回可见区。
        followLatestAfterKeyboardLayout()
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
        chatLayout.invalidateLayout()
        collectionView.layoutIfNeeded()

        // ChatLayout 官方示例也直接按布局的 contentSize 算底部偏移。
        // 从很远的历史位置 scrollToItem 时，末尾自适应气泡尚未测量，
        // 只能先滚到 Thinking 标题；直接钉内容底部后，末尾 cell 会被实例化，
        // keepContentOffsetAtBottomOnBatchUpdates 再接住随后的自适应高度修正。
        let bottomY = max(
            -collectionView.adjustedContentInset.top,
            chatLayout.collectionViewContentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: bottomY),
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
            switch item.kind {
            case .thinking:
                ThinkingTimelineRow { [weak self] in
                    self?.onThinkingOpen(item.messageID)
                }
                .environmentObject(Theme.shared)
            case .message:
                MessageRow(
                    message: item.message,
                    isHighlighted: item.isHighlighted,
                    visibleSegmentCount: item.visibleSegmentCount,
                    onAttachmentTap: { [weak self] attachment in
                        self?.onAttachmentTap(attachment)
                    }
                )
                .environmentObject(Theme.shared)
            }
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

    func interItemSpacing(
        _ chatLayout: CollectionViewChatLayout,
        of kind: ItemKind,
        after indexPath: IndexPath
    ) -> CGFloat? {
        guard kind == .cell, items.indices.contains(indexPath.item) else { return nil }
        return items[indexPath.item].kind == .thinking
            ? Theme.shared.metric.thinkingBubbleGap
            : nil
    }
}
