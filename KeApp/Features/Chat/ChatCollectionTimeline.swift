import ChatLayout
import Foundation
import SwiftUI
import UIKit

enum ChatTimelineItemKind: Equatable {
    case date(String)
    case thinking
    case tool(String)
    case message
}

enum ChatTimelineDate {
    static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "zh_CN")
        value.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return value
    }()

    static func dayKey(for message: Message) -> String? {
        guard message.serverTimeIsValid != false else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: message.time)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func visibleLabel(for date: Date, relativeTo now: Date = .now) -> String {
        guard let parts = dateParts(for: date) else { return "" }
        let monthDay = "\(parts.month)月\(parts.day)日"
        if calendar.isDate(date, inSameDayAs: now) {
            return "今天 · \(monthDay)"
        }
        if let yesterday = calendar.date(
            byAdding: .day,
            value: -1,
            to: calendar.startOfDay(for: now)
        ), calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 · \(monthDay)"
        }
        let currentYear = calendar.component(.year, from: now)
        return parts.year == currentYear
            ? monthDay
            : "\(parts.year)年\(monthDay)"
    }

    static func accessibilityLabel(for date: Date, relativeTo now: Date = .now) -> String {
        guard let parts = dateParts(for: date) else { return "日期" }
        let fullDate = "\(parts.year)年\(parts.month)月\(parts.day)日"
        if calendar.isDate(date, inSameDayAs: now) {
            return "日期，今天，\(fullDate)"
        }
        if let yesterday = calendar.date(
            byAdding: .day,
            value: -1,
            to: calendar.startOfDay(for: now)
        ), calendar.isDate(date, inSameDayAs: yesterday) {
            return "日期，昨天，\(fullDate)"
        }
        return "日期，\(fullDate)"
    }

    private static func dateParts(for date: Date) -> (year: Int, month: Int, day: Int)? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return nil }
        return (year, month, day)
    }
}

struct ChatTimelineItem: Identifiable, Equatable {
    let kind: ChatTimelineItemKind
    let message: Message
    let isHighlighted: Bool
    let visibleSegmentCount: Int?

    var id: String {
        switch kind {
        case let .date(dayKey):
            return "date::\(dayKey)"
        case .thinking:
            return "\(message.id)::thinking"
        case let .tool(toolRunID):
            return "\(message.id)::tool::\(toolRunID)"
        case .message:
            return "\(message.id)::message"
        }
    }

    var messageID: String { message.id }

    var toolRun: ChatToolRun? {
        guard case let .tool(toolRunID) = kind else { return nil }
        return message.toolRuns?.first(where: { $0.id == toolRunID })
    }

    static func make(
        messages: [Message],
        highlightedMessageID: String?,
        visibleSegmentCount: (Message) -> Int?
    ) -> [Self] {
        var result: [Self] = []
        var previousDayKey: String?

        for message in messages {
            if let dayKey = ChatTimelineDate.dayKey(for: message) {
                if dayKey != previousDayKey {
                    result.append(Self(
                        kind: .date(dayKey),
                        message: message,
                        isHighlighted: false,
                        visibleSegmentCount: nil
                    ))
                }
                previousDayKey = dayKey
            }
            result.append(contentsOf: make(
                message: message,
                isHighlighted: highlightedMessageID == message.id,
                visibleSegmentCount: visibleSegmentCount(message)
            ))
        }
        return result
    }

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
        if message.sender == .me {
            result.append(messageItem(
                message: message,
                isHighlighted: isHighlighted,
                visibleSegmentCount: visibleSegmentCount
            ))
        }
        for toolRun in message.toolRuns ?? [] where !toolRun.id.isEmpty {
            result.append(Self(
                kind: .tool(toolRun.id),
                message: message,
                isHighlighted: false,
                visibleSegmentCount: nil
            ))
        }
        if message.sender == .ke {
            result.append(messageItem(
                message: message,
                isHighlighted: isHighlighted,
                visibleSegmentCount: visibleSegmentCount
            ))
        }
        return result
    }

    private static func messageItem(
        message: Message,
        isHighlighted: Bool,
        visibleSegmentCount: Int?
    ) -> Self {
        Self(
            kind: .message,
            message: message,
            isHighlighted: isHighlighted,
            visibleSegmentCount: visibleSegmentCount
        )
    }

    private static func hasThinking(_ message: Message) -> Bool {
        [message.thoughtSummary, message.thoughtNote].contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

enum ChatTimelineFollowPolicy {
    static func shouldFollowLatest(
        timelineChanged: Bool,
        wasFollowingLatest: Bool,
        appendedOwnMessage: Bool,
        mayAutoFollow: Bool
    ) -> Bool {
        mayAutoFollow
            && timelineChanged
            && (wasFollowingLatest || appendedOwnMessage)
    }
}

enum ChatTimelineScrollControlPolicy {
    static func shouldShow(
        distanceFromLatest: CGFloat,
        revealDistance: CGFloat
    ) -> Bool {
        distanceFromLatest > revealDistance
    }
}

struct ChatCollectionTimeline: UIViewControllerRepresentable, Equatable {
    let items: [ChatTimelineItem]
    let streamRevision: Int
    let suppressAutoScrollUntil: Date
    let inputFocused: Bool
    let highlightedMessageID: String?
    let scrollToLatestRequest: Int
    let onThinkingOpen: (String) -> Void
    let onAttachmentTap: (ChatAttachment) -> Void
    let onBackgroundTap: () -> Void
    let onScrollToLatestVisibilityChanged: (Bool) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        // ChatViewModel 还承载模型选择、上传和设置状态。那些发布会让父视图
        // 重算，但不应重新触碰底下的 UIKit 时间线；透明材质在无关更新时
        // 被重新提交，会在真机上表现为聊天区闪一下。闭包不参与视觉身份，
        // 真正会改变时间线的输入都在这里逐项比较。
        lhs.items == rhs.items
            && lhs.streamRevision == rhs.streamRevision
            && lhs.suppressAutoScrollUntil == rhs.suppressAutoScrollUntil
            && lhs.inputFocused == rhs.inputFocused
            && lhs.highlightedMessageID == rhs.highlightedMessageID
            && lhs.scrollToLatestRequest == rhs.scrollToLatestRequest
    }

    func makeUIViewController(context: Context) -> ChatCollectionTimelineController {
        ChatCollectionTimelineController(
            items: items,
            streamRevision: streamRevision,
            inputFocused: inputFocused,
            highlightedMessageID: highlightedMessageID,
            scrollToLatestRequest: scrollToLatestRequest,
            onThinkingOpen: onThinkingOpen,
            onAttachmentTap: onAttachmentTap,
            onBackgroundTap: onBackgroundTap,
            onScrollToLatestVisibilityChanged: onScrollToLatestVisibilityChanged
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
            scrollToLatestRequest: scrollToLatestRequest,
            onThinkingOpen: onThinkingOpen,
            onAttachmentTap: onAttachmentTap,
            onBackgroundTap: onBackgroundTap,
            onScrollToLatestVisibilityChanged: onScrollToLatestVisibilityChanged
        )
    }
}

/// `UIHostingConfiguration` normally relies on UIKit's deferred self-sizing pass.
/// ChatLayout needs the final height during the same layout pass, otherwise a very
/// tall wrapped message can keep the 40pt estimate and draw over the following row.
/// Measure the hosted SwiftUI hierarchy at the exact timeline width before handing
/// the attributes back to ChatLayout.
final class ChatTimelineHostingCell: UICollectionViewCell {
    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        guard let fitted = layoutAttributes.copy() as? ChatLayoutAttributes else {
            return super.preferredLayoutAttributesFitting(layoutAttributes)
        }

        let width = fitted.size.width
        guard width > 0 else { return fitted }

        // A reused hosting view may still carry the previous proposal. ViewThatFits
        // must see today's exact row width before it decides between a compact and
        // wrapped bubble, otherwise the height can be measured from stale bounds.
        contentView.bounds.size = CGSize(
            width: width,
            height: max(contentView.bounds.height, 1)
        )
        contentView.setNeedsLayout()
        contentView.layoutIfNeeded()
        let measured = contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        fitted.size = CGSize(
            width: width,
            height: ceil(max(measured.height, 1))
        )
        return fitted
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentConfiguration = nil
    }
}

final class ChatCollectionTimelineController: UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
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
    private var onScrollToLatestVisibilityChanged: (Bool) -> Void
    private var scrollToLatestRequest: Int
    private var didScrollToLatest = false
    private var lastTimelineHeight: CGFloat = 0
    private var pendingFollowLatestAfterLayout = false
    private var followsLatestByIntent = true
    private var isScrollingToLatest = false
    private var lastPublishedScrollControlVisibility: Bool?

    init(
        items: [ChatTimelineItem],
        streamRevision: Int,
        inputFocused: Bool,
        highlightedMessageID: String?,
        scrollToLatestRequest: Int,
        onThinkingOpen: @escaping (String) -> Void,
        onAttachmentTap: @escaping (ChatAttachment) -> Void,
        onBackgroundTap: @escaping () -> Void,
        onScrollToLatestVisibilityChanged: @escaping (Bool) -> Void
    ) {
        self.items = items
        self.streamRevision = streamRevision
        self.inputFocused = inputFocused
        self.highlightedMessageID = highlightedMessageID
        self.scrollToLatestRequest = scrollToLatestRequest
        self.onThinkingOpen = onThinkingOpen
        self.onAttachmentTap = onAttachmentTap
        self.onBackgroundTap = onBackgroundTap
        self.onScrollToLatestVisibilityChanged = onScrollToLatestVisibilityChanged
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
        collectionView.delegate = self
        collectionView.register(
            ChatTimelineHostingCell.self,
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
        let shouldPreserveLatest = followsLatestByIntent

        super.viewDidLayoutSubviews()
        let currentHeight = collectionView.bounds.height
        lastTimelineHeight = currentHeight

        if pendingFollowLatestAfterLayout, !items.isEmpty {
            pendingFollowLatestAfterLayout = false
            chatLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            scrollToLatest(animated: false)
            return
        }

        guard shouldPreserveLatest,
              abs(currentHeight - previousHeight) > 0.5,
              !items.isEmpty else {
            publishScrollControlVisibility()
            return
        }

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
        scrollToLatestRequest newScrollToLatestRequest: Int,
        onThinkingOpen: @escaping (String) -> Void,
        onAttachmentTap: @escaping (ChatAttachment) -> Void,
        onBackgroundTap: @escaping () -> Void,
        onScrollToLatestVisibilityChanged: @escaping (Bool) -> Void
    ) {
        self.onThinkingOpen = onThinkingOpen
        self.onAttachmentTap = onAttachmentTap
        self.onBackgroundTap = onBackgroundTap
        self.onScrollToLatestVisibilityChanged = onScrollToLatestVisibilityChanged

        let oldItems = items
        let oldStreamRevision = streamRevision
        let oldHighlightedMessageID = highlightedMessageID
        let wasFollowingLatest = followsLatestByIntent || isNearLatest
        let requestedScrollToLatest = scrollToLatestRequest != newScrollToLatestRequest
        items = newItems
        streamRevision = newStreamRevision
        inputFocused = newInputFocused
        highlightedMessageID = newHighlightedMessageID
        scrollToLatestRequest = newScrollToLatestRequest

        let mayAutoFollow = Date.now >= suppressAutoScrollUntil
        let oldIDs = oldItems.map(\.id)
        let newIDs = newItems.map(\.id)
        let appendedItems = newIDs.starts(with: oldIDs)
            ? Array(newItems.dropFirst(oldItems.count))
            : []
        let oldIDSet = Set(oldIDs)
        let retainedNewIDs = newIDs.filter { oldIDSet.contains($0) }
        let insertedIndexes = newIDs.indices.filter { !oldIDSet.contains(newIDs[$0]) }
        let isInsertionOnly = retainedNewIDs == oldIDs && !insertedIndexes.isEmpty
        let appendedOwnMessage = appendedItems.contains { $0.message.sender == .me }
        let timelineChanged = oldIDs != newIDs || oldStreamRevision != newStreamRevision
        let shouldFollowLatest = ChatTimelineFollowPolicy.shouldFollowLatest(
            timelineChanged: timelineChanged,
            wasFollowingLatest: wasFollowingLatest,
            appendedOwnMessage: appendedOwnMessage,
            mayAutoFollow: mayAutoFollow
        )
        if shouldFollowLatest {
            followsLatestByIntent = true
        }

        let hasStableIdentity = oldIDs == newIDs
        if hasStableIdentity {
            reloadChangedItems(from: oldItems, followLatest: shouldFollowLatest)
        } else if isInsertionOnly {
            insertItems(
                at: insertedIndexes,
                followLatest: shouldFollowLatest
            )
        } else {
            let snapshot = shouldFollowLatest
                ? nil
                : chatLayout.getContentOffsetSnapshot(from: .top)
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
            if shouldFollowLatest {
                scrollToLatest(animated: false)
            } else if let snapshot {
                chatLayout.restoreContentOffset(with: snapshot)
            }
        }

        if oldHighlightedMessageID != newHighlightedMessageID,
           let newHighlightedMessageID,
           let index = newItems.firstIndex(where: {
               $0.messageID == newHighlightedMessageID && $0.kind == .message
           }) {
            followsLatestByIntent = false
            collectionView.scrollToItem(
                at: IndexPath(item: index, section: 0),
                at: .centeredVertically,
                animated: true
            )
        }

        if requestedScrollToLatest {
            DispatchQueue.main.async { [weak self] in
                self?.scrollToLatest(animated: !UIAccessibility.isReduceMotionEnabled)
            }
        } else {
            publishScrollControlVisibility()
        }
    }

    private var maximumContentOffsetY: CGFloat {
        max(
            -collectionView.adjustedContentInset.top,
            chatLayout.collectionViewContentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
    }

    private var distanceFromLatest: CGFloat {
        max(0, maximumContentOffsetY - collectionView.contentOffset.y)
    }

    private var isNearLatest: Bool {
        guard collectionView.bounds.height > 0 else { return true }
        return distanceFromLatest <= Theme.shared.metric.touchTarget
    }

    private func insertItems(at indexes: [Int], followLatest: Bool) {
        let positionSnapshot = followLatest
            ? nil
            : chatLayout.getContentOffsetSnapshot(from: .top)
        let paths = indexes.map { IndexPath(item: $0, section: 0) }

        UIView.performWithoutAnimation {
            collectionView.performBatchUpdates {
                collectionView.insertItems(at: paths)
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

    private func requestFollowLatestAfterLayout() {
        followsLatestByIntent = true
        pendingFollowLatestAfterLayout = true
        publishScrollControlVisibility(forceHidden: true)
        view.setNeedsLayout()
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
            as? CGRect,
              endFrame.minY < UIScreen.main.bounds.maxY else { return }
        // UIKit 通知比 SwiftUI FocusState 稳定：即使用户从历史位置点输入框，
        // 也要等系统确定键盘终点后，把最新消息带回可见区。
        requestFollowLatestAfterLayout()
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
        followsLatestByIntent = true
        chatLayout.invalidateLayout()
        collectionView.layoutIfNeeded()

        // ChatLayout 官方示例也直接按布局的 contentSize 算底部偏移。
        // 从很远的历史位置 scrollToItem 时，末尾自适应气泡尚未测量，
        // 只能先滚到 Thinking 标题；直接钉内容底部后，末尾 cell 会被实例化，
        // keepContentOffsetAtBottomOnBatchUpdates 再接住随后的自适应高度修正。
        let bottomY = maximumContentOffsetY
        let shouldAnimate = animated
            && abs(collectionView.contentOffset.y - bottomY) > 0.5
        isScrollingToLatest = shouldAnimate
        publishScrollControlVisibility(forceHidden: true)
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: bottomY),
            animated: shouldAnimate
        )
        if !shouldAnimate {
            isScrollingToLatest = false
            publishScrollControlVisibility()
        }
    }

    private func publishScrollControlVisibility(forceHidden: Bool = false) {
        let shouldShow = !forceHidden
            && !isScrollingToLatest
            && ChatTimelineScrollControlPolicy.shouldShow(
                distanceFromLatest: distanceFromLatest,
                revealDistance: Theme.shared.metric.scrollToLatestRevealDistance
            )
        guard shouldShow != lastPublishedScrollControlVisibility else { return }
        lastPublishedScrollControlVisibility = shouldShow
        let callback = onScrollToLatestVisibilityChanged
        DispatchQueue.main.async {
            callback(shouldShow)
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isScrollingToLatest = false
        followsLatestByIntent = false
        publishScrollControlVisibility()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.isDragging || scrollView.isDecelerating {
            followsLatestByIntent = isNearLatest
        }
        publishScrollControlVisibility(forceHidden: isScrollingToLatest)
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        guard !decelerate else { return }
        followsLatestByIntent = isNearLatest
        publishScrollControlVisibility()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        followsLatestByIntent = isNearLatest
        publishScrollControlVisibility()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard isScrollingToLatest else {
            publishScrollControlVisibility()
            return
        }
        isScrollingToLatest = false
        scrollToLatest(animated: false)
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
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "ChatTimelineCell",
            for: indexPath
        ) as? ChatTimelineHostingCell else {
            assertionFailure("Chat timeline registered an unexpected cell type")
            return UICollectionViewCell()
        }
        let item = items[indexPath.item]
        cell.backgroundColor = .clear
        cell.contentConfiguration = UIHostingConfiguration {
            switch item.kind {
            case .date:
                ChatDateDividerRow(date: item.message.time)
                    .environmentObject(Theme.shared)
                    .accessibilityIdentifier("chat-date-\(item.id)")
            case .thinking:
                ThinkingTimelineRow { [weak self] in
                    self?.onThinkingOpen(item.messageID)
                }
                .environmentObject(Theme.shared)
                .accessibilityIdentifier("thinking-entry-\(item.messageID)")
            case .tool:
                if let toolRun = item.toolRun {
                    ChatToolStatusRow(toolRun: toolRun)
                        .environmentObject(Theme.shared)
                        .accessibilityIdentifier("chat-tool-run-\(toolRun.id)")
                }
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
        switch items[indexPath.item].kind {
        case .date:
            return Theme.shared.metric.gapS
        case .thinking:
            return Theme.shared.metric.thinkingBubbleGap
        case .tool:
            return Theme.shared.metric.gapS
        case .message:
            return nil
        }
    }
}
