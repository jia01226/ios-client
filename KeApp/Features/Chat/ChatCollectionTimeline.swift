import ChatLayout
import Foundation
import SwiftUI
import UIKit

enum ChatTimelineItemKind: Equatable {
    case date(String)
    /// 111：她隔了一个钟头以上才回，中间放一行「你消失了 1 小时 36 分」
    case gap(Int)
    case thinking
    case tool(String)
    case message
    /// 121：柯的一句按段切成几个气泡时，第 2 个起每个气泡自己占一行（第 1 个仍是 .message）。
    /// 一个个冒出来就是一行行插进来，和来了新消息一样；已经在屏幕上的气泡不重排、不变大小。
    case segment(Int)
}

/// 121：这一行画柯那句话的第几个气泡。时间、复制那一行只跟在最后一个气泡下面，
/// 所以前面的气泡从冒出来到最后都是同一个样子，后面的冒出来时不用改前面的。
struct ChatBubblePart: Equatable {
    let index: Int
    let count: Int
    /// 这个气泡里的字；日记卡、只有附件、还在写的那一行没有
    let text: String?

    var isFirst: Bool { index == 0 }
    var isLast: Bool { index >= count - 1 }
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

/// 127：ChatView 每重画一次（键盘、回到最新按钮出现、抽屉开关……）都会把整段记录重新切成时间线：
/// 每条算一次日期、柯的每条再切一次气泡。记录长了一次好几毫秒，正好掉在滑动或抽屉动画的那一帧上。
/// 这里记住上一次的输入和结果，输入没变就原样返回。数组/字典没改过时比较只看是不是同一块存储，几乎不花时间。
@MainActor
final class ChatTimelineItemsCache {
    private struct Key: Equatable {
        let messages: [Message]
        let highlightedMessageID: String?
        let quotedIDs: [Int]
        let pinnedIDs: Set<Int>
        let revealCounts: [String: Int]?
    }

    private var key: Key?
    private var cached: [ChatTimelineItem] = []
    private(set) var rebuildCount = 0

    func items(
        messages: [Message],
        highlightedMessageID: String?,
        quotedIDs: [Int],
        pinnedIDs: Set<Int>,
        revealCounts: [String: Int]?,
        visibleSegmentCount: (Message) -> Int?
    ) -> [ChatTimelineItem] {
        let next = Key(
            messages: messages,
            highlightedMessageID: highlightedMessageID,
            quotedIDs: quotedIDs,
            pinnedIDs: pinnedIDs,
            revealCounts: revealCounts
        )
        if let key, key == next { return cached }
        key = next
        rebuildCount += 1
        cached = ChatTimelineItem.make(
            messages: messages,
            highlightedMessageID: highlightedMessageID,
            quotedIDs: Set(quotedIDs),
            pinnedIDs: pinnedIDs,
            visibleSegmentCount: visibleSegmentCount
        )
        return cached
    }
}

struct ChatTimelineItem: Identifiable, Equatable {
    let kind: ChatTimelineItemKind
    let message: Message
    let isHighlighted: Bool
    /// 121：消息那几行各画哪个气泡；日期、空白、Thinking、工具卡没有
    var part: ChatBubblePart? = nil
    var isQuoted = false
    /// 112：这一轮已钉住，下个窗会带上
    var isPinned = false

    var id: String {
        switch kind {
        case let .date(dayKey):
            return "date::\(dayKey)"
        case .gap:
            return "\(message.id)::gap"
        case .thinking:
            return "\(message.id)::thinking"
        case let .tool(toolRunID):
            return "\(message.id)::tool::\(toolRunID)"
        case .message:
            // 125：还在等的那一行（「发送中」「等待接回」）和落下来的第一个气泡不算同一行：落下来时删掉占位、
            // 插进第一个气泡，不在原位重画。原位重画又赶上上面同时插进 Thinking（记录里才带来的）时，
            // 占位那格会留在屏上——她截图里「20:24 等待接回」底下直接是第二个气泡，第一句「过来」没出来。
            return message.isAwaitingReply ? "\(message.id)::awaiting" : "\(message.id)::message"
        case let .segment(index):
            return "\(message.id)::message::\(index)"
        }
    }

    /// 121：只比这一行真正画出来的东西。拉回记录时本机那条会换成服务器那条（沿用本机 id，
    /// 时间差几秒、多了 Thinking 原文之类），气泡一样就不重画——已经冒出来的气泡原样不动，
    /// 不闪、不跳，也不会重新一个个冒。
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.kind == rhs.kind,
              lhs.message.id == rhs.message.id,
              lhs.isHighlighted == rhs.isHighlighted,
              lhs.isQuoted == rhs.isQuoted,
              lhs.isPinned == rhs.isPinned,
              lhs.part == rhs.part else { return false }
        switch lhs.kind {
        case .date, .gap, .thinking:
            // 日期按天、空白按分钟都在 kind 里；Thinking 这一行只是个入口，内容在弹窗里现读
            return true
        case .tool:
            return lhs.toolRun == rhs.toolRun
        case .message, .segment:
            return drawsSameRow(lhs.message, rhs.message, part: lhs.part)
        }
    }

    private static func drawsSameRow(_ a: Message, _ b: Message, part: ChatBubblePart?) -> Bool {
        guard a.serverID == b.serverID,
              a.sender == b.sender,
              a.isStreaming == b.isStreaming,
              a.deliveryState == b.deliveryState,
              a.text.isEmpty == b.text.isEmpty else { return false }
        // 她的话整条就是一个气泡（柯的字已经在 part.text 里比过了）
        if a.sender == .me, a.text != b.text { return false }
        // 附件（照片、塔罗牌、日记卡）画在第一个气泡里
        if part?.isFirst ?? true, (a.attachments ?? []) != (b.attachments ?? []) { return false }
        // 时间只写在最后一个气泡下面，按分钟比——和屏幕上显示的一样
        if part?.isLast ?? true, minute(of: a.time) != minute(of: b.time) { return false }
        return true
    }

    private static func minute(of date: Date) -> Int {
        Int((date.timeIntervalSinceReferenceDate / 60).rounded(.down))
    }

    var messageID: String { message.id }

    var toolRun: ChatToolRun? {
        guard case let .tool(toolRunID) = kind else { return nil }
        return message.toolRuns?.first(where: { $0.id == toolRunID })
    }

    static func make(
        messages: [Message],
        highlightedMessageID: String?,
        quotedIDs: Set<Int> = [],
        pinnedIDs: Set<Int> = [],
        visibleSegmentCount: (Message) -> Int?
    ) -> [Self] {
        var result: [Self] = []
        var previousDayKey: String?
        var previousTime: Date?

        for message in messages {
            var newDay = false
            if let dayKey = ChatTimelineDate.dayKey(for: message) {
                if dayKey != previousDayKey {
                    newDay = true
                    result.append(Self(
                        kind: .date(dayKey),
                        message: message,
                        isHighlighted: false
                    ))
                }
                previousDayKey = dayKey
            }
            if message.sender == .me, !newDay, let previousTime {
                let minutes = Int(message.time.timeIntervalSince(previousTime) / 60)
                if minutes >= 60 {
                    result.append(Self(kind: .gap(minutes), message: message, isHighlighted: false))
                }
            }
            previousTime = message.time
            result.append(contentsOf: make(
                message: message,
                isHighlighted: highlightedMessageID == message.id,
                visibleSegmentCount: visibleSegmentCount(message)
            ))
        }
        return result.map { item in
            var item = item
            item.isQuoted = item.message.serverID.map(quotedIDs.contains) ?? false
            item.isPinned = item.message.serverID.map(pinnedIDs.contains) ?? false
            return item
        }
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
                isHighlighted: false
            ))
        }
        if message.sender == .me {
            result.append(contentsOf: messageItems(
                message: message,
                isHighlighted: isHighlighted,
                visibleSegmentCount: visibleSegmentCount
            ))
        }
        for toolRun in message.toolRuns ?? [] where !toolRun.id.isEmpty {
            result.append(Self(
                kind: .tool(toolRun.id),
                message: message,
                isHighlighted: false
            ))
        }
        if message.sender == .ke {
            result.append(contentsOf: messageItems(
                message: message,
                isHighlighted: isHighlighted,
                visibleSegmentCount: visibleSegmentCount
            ))
        }
        return result
    }

    /// 121：柯的一句切成几个气泡就出几行，一个个冒出来时只出已经冒出来的那几行。
    /// 她的话、日记卡、只有附件的、还在写的那一行（只有时间和「发送中」）都只占一行。
    private static func messageItems(
        message: Message,
        isHighlighted: Bool,
        visibleSegmentCount: Int?
    ) -> [Self] {
        let segments = message.bubbleSegments
        guard message.sender == .ke, message.unlockedDiary == nil, segments.count > 1 else {
            return [Self(
                kind: .message,
                message: message,
                isHighlighted: isHighlighted,
                part: ChatBubblePart(index: 0, count: 1, text: segments.first)
            )]
        }
        let shown = min(segments.count, max(1, visibleSegmentCount ?? segments.count))
        return (0..<shown).map { index in
            Self(
                kind: index == 0 ? .message : .segment(index),
                message: message,
                isHighlighted: isHighlighted,
                part: ChatBubblePart(index: index, count: segments.count, text: segments[index])
            )
        }
    }

    private static func hasThinking(_ message: Message) -> Bool {
        [message.thoughtSummary, message.thoughtNote].contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// 121：时间线从旧的一排变成新的一排要动哪几格。只要留下来的那些前后顺序没变，就只删掉走了的、
/// 插进新来的、重画内容变了的——已经在屏幕上又没变的格子一个都不碰（125 起重画另起一批，见 apply）。
/// 以前一边插一边有格子变（占位换成第一个气泡、后面的气泡同时插进来）时，变了的那格会漏掉不重画。
struct ChatTimelineChanges: Equatable {
    /// 旧下标
    var deleted: [Int] = []
    /// 新下标
    var inserted: [Int] = []
    /// 旧下标：还在，但画出来不一样了
    var reloaded: [Int] = []
    /// 125：同样这几格的新下标（和 reloaded 一一对应）。重画单独一批、在删插之后做，用的是这个。
    var reloadedAfter: [Int] = []

    var isEmpty: Bool { deleted.isEmpty && inserted.isEmpty && reloaded.isEmpty }

    /// nil：有重复的 id，或者留下来的前后顺序变了——只能整页重载。
    static func between(_ old: [ChatTimelineItem], _ new: [ChatTimelineItem]) -> ChatTimelineChanges? {
        let oldIDs = old.map(\.id)
        let newIDs = new.map(\.id)
        var oldIndex: [String: Int] = [:]
        for (index, id) in oldIDs.enumerated() {
            if oldIndex.updateValue(index, forKey: id) != nil { return nil }
        }
        var newIndex: [String: Int] = [:]
        for (index, id) in newIDs.enumerated() {
            if newIndex.updateValue(index, forKey: id) != nil { return nil }
        }

        var changes = ChatTimelineChanges()
        var retainedInOldOrder: [String] = []
        for (index, id) in oldIDs.enumerated() {
            guard let newPosition = newIndex[id] else {
                changes.deleted.append(index)
                continue
            }
            retainedInOldOrder.append(id)
            if old[index] != new[newPosition] {
                changes.reloaded.append(index)
                changes.reloadedAfter.append(newPosition)
            }
        }
        let retainedInNewOrder = newIDs.filter { oldIndex[$0] != nil }
        guard retainedInOldOrder == retainedInNewOrder else { return nil }
        changes.inserted = newIDs.indices.filter { oldIndex[newIDs[$0]] == nil }
        return changes
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
    var onRecall: (Message) -> Void = { _ in }
    var onSaveQuote: (Message) -> Void = { _ in }
    var onTogglePin: (Message) -> Void = { _ in }
    /// 112：在聊天记录上往左划，拉出设置抽屉
    var onDrawerPan: (ChatDrawerPan) -> Void = { _ in }
    let onBackgroundTap: () -> Void
    let onScrollToLatestVisibilityChanged: (Bool) -> Void
    /// 126：时间线铺到整屏，顶栏和输入栏浮在上面。这两条是浮栏的边（全局坐标 = 窗口坐标）：
    /// 顶上浮栏的下沿、输入胶囊的上沿。上下留白在 UIKit 那边按时间线自己在窗口里的位置算。
    var chromeTopEdge: CGFloat = 0
    var chromeBottomEdge: CGFloat = 0

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
            && lhs.chromeTopEdge == rhs.chromeTopEdge
            && lhs.chromeBottomEdge == rhs.chromeBottomEdge
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
            onRecall: onRecall,
            onSaveQuote: onSaveQuote,
            onTogglePin: onTogglePin,
            onDrawerPan: onDrawerPan,
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
            onRecall: onRecall,
            onSaveQuote: onSaveQuote,
            onTogglePin: onTogglePin,
            onDrawerPan: onDrawerPan,
            onBackgroundTap: onBackgroundTap,
            onScrollToLatestVisibilityChanged: onScrollToLatestVisibilityChanged
        )
        controller.setChromeEdges(top: chromeTopEdge, bottom: chromeBottomEdge)
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
    private var onRecall: (Message) -> Void
    private var onSaveQuote: (Message) -> Void
    private var onTogglePin: (Message) -> Void
    private var onDrawerPan: (ChatDrawerPan) -> Void
    private var onBackgroundTap: () -> Void
    private var onScrollToLatestVisibilityChanged: (Bool) -> Void
    private var scrollToLatestRequest: Int
    private var didScrollToLatest = false
    private var lastTimelineHeight: CGFloat = 0
    private var pendingFollowLatestAfterLayout = false
    private var followsLatestByIntent = true
    private var isScrollingToLatest = false
    private var lastPublishedScrollControlVisibility: Bool?
    private var chromeInsets: UIEdgeInsets = .zero
    private var chromeEdges: (top: CGFloat, bottom: CGFloat) = (0, 0)

    init(
        items: [ChatTimelineItem],
        streamRevision: Int,
        inputFocused: Bool,
        highlightedMessageID: String?,
        scrollToLatestRequest: Int,
        onThinkingOpen: @escaping (String) -> Void,
        onAttachmentTap: @escaping (ChatAttachment) -> Void,
        onRecall: @escaping (Message) -> Void,
        onSaveQuote: @escaping (Message) -> Void = { _ in },
        onTogglePin: @escaping (Message) -> Void = { _ in },
        onDrawerPan: @escaping (ChatDrawerPan) -> Void = { _ in },
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
        self.onRecall = onRecall
        self.onSaveQuote = onSaveQuote
        self.onTogglePin = onTogglePin
        self.onDrawerPan = onDrawerPan
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
        // 126：时间线铺到状态栏和屏幕底下面；上下留白全由 SwiftUI 量好的浮栏位置给（applyChromeInsets），
        // 系统不再按安全区另加一份。
        collectionView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 26.0, *) {
            // 126：浮栏自己是圆角玻璃；系统在状态栏/底边加的那层渐隐（一整条横着的白雾）不要
            collectionView.topEdgeEffect.isHidden = true
            collectionView.bottomEdgeEffect.isHidden = true
        }
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

        // 112：往左划拉出设置抽屉。只认明显的横向左划，和上下滚动、长按菜单同时存在。
        let drawerPan = UIPanGestureRecognizer(target: self, action: #selector(didPanForDrawer(_:)))
        drawerPan.cancelsTouchesInView = false
        drawerPan.delegate = self
        collectionView.addGestureRecognizer(drawerPan)

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
        // 126：键盘起落时时间线自己的高度变了，浮栏的边也跟着动，留白重算（下面照旧会落回最新）
        applyChromeInsets(chromeInsetsForCurrentFrame(), scrollIfFollowing: false)

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
        onRecall: @escaping (Message) -> Void,
        onSaveQuote: @escaping (Message) -> Void = { _ in },
        onTogglePin: @escaping (Message) -> Void = { _ in },
        onDrawerPan: @escaping (ChatDrawerPan) -> Void = { _ in },
        onBackgroundTap: @escaping () -> Void,
        onScrollToLatestVisibilityChanged: @escaping (Bool) -> Void
    ) {
        self.onThinkingOpen = onThinkingOpen
        self.onAttachmentTap = onAttachmentTap
        self.onRecall = onRecall
        self.onSaveQuote = onSaveQuote
        self.onTogglePin = onTogglePin
        self.onDrawerPan = onDrawerPan
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

        // 121：一个个冒出来的气泡是插进来的新格子；拉回记录换成服务器那条时，没变的格子不碰。
        if let changes = ChatTimelineChanges.between(oldItems, newItems) {
            apply(changes, followLatest: shouldFollowLatest)
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

    /// 126：浮栏的边（窗口坐标）换成这条时间线上下要留的白
    func setChromeEdges(top: CGFloat, bottom: CGFloat) {
        chromeEdges = (top, bottom)
        guard isViewLoaded else { return }
        applyChromeInsets(chromeInsetsForCurrentFrame(), scrollIfFollowing: true)
    }

    private func chromeInsetsForCurrentFrame() -> UIEdgeInsets {
        guard view.window != nil, chromeEdges.bottom > 0 else { return chromeInsets }
        let frame = view.convert(view.bounds, to: nil)
        return Self.chromeInsets(timelineFrame: frame, chromeTop: chromeEdges.top, chromeBottom: chromeEdges.bottom)
    }

    /// 顶上让过标题胶囊（和提示条），底下让过输入胶囊（和它下面的底栏、Home 条）
    nonisolated static func chromeInsets(timelineFrame: CGRect, chromeTop: CGFloat, chromeBottom: CGFloat) -> UIEdgeInsets {
        let top = max(0, chromeTop - timelineFrame.minY)
        let bottom = max(0, timelineFrame.maxY - chromeBottom)
        return UIEdgeInsets(top: top.rounded(), left: 0, bottom: bottom.rounded(), right: 0)
    }

    /// 浮栏位置一变（键盘起落、提示条出现、输入框长高、底栏收起），上下留白跟着变；
    /// 本来停在最新的，换完还停在最新，第一条、最后一条都能完整滚出来。
    private func applyChromeInsets(_ insets: UIEdgeInsets, scrollIfFollowing: Bool) {
        guard abs(insets.top - chromeInsets.top) > 0.5 || abs(insets.bottom - chromeInsets.bottom) > 0.5 else { return }
        let wasFollowingLatest = followsLatestByIntent || isNearLatest
        chromeInsets = insets
        collectionView.contentInset = insets
        collectionView.verticalScrollIndicatorInsets = insets
        if scrollIfFollowing && wasFollowingLatest && !items.isEmpty && !collectionView.isDragging {
            scrollToLatest(animated: false)
        } else if wasFollowingLatest && !items.isEmpty {
            // 布局里改的：等这一轮布局完再落回最新，不在 layoutSubviews 里再套一层布局
            requestFollowLatestAfterLayout()
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

    /// 插新格子、删旧格子，再重画变了的格子（125：两批）；和来新消息走的是同一条路
    /// （不带动画，跟着最新时落到最底，翻旧记录时按顶部快照留在原处）。
    private func apply(_ changes: ChatTimelineChanges, followLatest: Bool) {
        guard !changes.isEmpty else {
            if followLatest { scrollToLatest(animated: false) }
            return
        }

        let positionSnapshot = followLatest
            ? nil
            : chatLayout.getContentOffsetSnapshot(from: .top)
        // UIKit 约定：删除用更新前的下标，插入用更新后的下标
        let deleted = changes.deleted.map { IndexPath(item: $0, section: 0) }
        let inserted = changes.inserted.map { IndexPath(item: $0, section: 0) }
        // 125：重画放在删插之后单独一批，用更新后的下标——这一批里什么都不挪，前后下标一样。
        // 混在一批里、重画的那格又被上面插进来的挤下去一格时，ChatLayout 按新下标记「重画」、按旧下标藏旧格子，
        // 两边对不上，旧格子就留在屏上（ChatLayout 自己的示例也是分两批：先删插，再重画）。
        let reloaded = changes.reloadedAfter.map { IndexPath(item: $0, section: 0) }

        UIView.performWithoutAnimation {
            if !deleted.isEmpty || !inserted.isEmpty {
                collectionView.performBatchUpdates {
                    if !deleted.isEmpty { collectionView.deleteItems(at: deleted) }
                    if !inserted.isEmpty { collectionView.insertItems(at: inserted) }
                }
            }
            collectionView.performBatchUpdates {
                if !reloaded.isEmpty { collectionView.reloadItems(at: reloaded) }
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

    @objc private func didPanForDrawer(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: view).x
        switch pan.state {
        case .changed:
            onDrawerPan(.changed(translation))
        case .ended:
            onDrawerPan(.ended(translation, velocity: pan.velocity(in: view).x))
        case .cancelled, .failed:
            onDrawerPan(.cancelled)
        default:
            break
        }
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
            case let .gap(minutes):
                ChatGapRow(minutes: minutes)
                    .environmentObject(Theme.shared)
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
            case .message, .segment:
                // 121：每个气泡一格。格子没重画时手里那份消息可能是本机旧的一版，
                // 撤回、收语录、钉住都按 id 取时间线里最新的那条。
                MessageRow(
                    message: item.message,
                    isHighlighted: item.isHighlighted,
                    visibleSegmentCount: nil,
                    onAttachmentTap: { [weak self] attachment in
                        self?.onAttachmentTap(attachment)
                    },
                    onRecall: { [weak self] message in
                        guard let self else { return }
                        self.onRecall(self.latest(message))
                    },
                    onSaveQuote: { [weak self] message in
                        guard let self else { return }
                        self.onSaveQuote(self.latest(message))
                    },
                    isQuoted: item.isQuoted,
                    onTogglePin: { [weak self] message in
                        guard let self else { return }
                        self.onTogglePin(self.latest(message))
                    },
                    isPinned: item.isPinned,
                    part: item.part
                )
                .environmentObject(Theme.shared)
#if DEBUG
                .onAppear { ChatRecoveryUITestTiming.shared.appeared(item.message) }
#endif
            }
        }
        .margins(.all, 0)
        return cell
    }

    private func latest(_ message: Message) -> Message {
        items.first { $0.messageID == message.id && $0.part != nil }?.message ?? message
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
    ) {
        // 125：删掉的格子（落下来的回复换走的占位）最后是透明的，万一这一下带了动画也不会留在屏上。
        // 不接这个代理时 ChatLayout 默认就是这样；插进来的格子仍旧不淡入。
        originalAttributes.alpha = 0
    }

    func interItemSpacing(
        _ chatLayout: CollectionViewChatLayout,
        of kind: ItemKind,
        after indexPath: IndexPath
    ) -> CGFloat? {
        guard kind == .cell, items.indices.contains(indexPath.item) else { return nil }
        switch items[indexPath.item].kind {
        case .date, .gap:
            return Theme.shared.metric.gapS
        case .thinking:
            return Theme.shared.metric.thinkingBubbleGap
        case .tool:
            return Theme.shared.metric.gapS
        case .message, .segment:
            // 121：同一句的几个气泡之间还是原来那条小缝。只看自己是不是最后一个，不看后面是谁，
            // 后面的气泡插进来时前面这格的间距不用变。
            if let part = items[indexPath.item].part, !part.isLast {
                return Theme.shared.metric.splitBubbleGap
            }
            return nil
        }
    }
}

/// 112：聊天页往左划拉设置抽屉的过程。手指往左时 translation 为负。
enum ChatDrawerPan: Equatable {
    case changed(CGFloat)
    case ended(CGFloat, velocity: CGFloat)
    case cancelled
}

extension ChatCollectionTimelineController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              pan.view === collectionView else { return true }
        let velocity = pan.velocity(in: view)
        let start = pan.location(in: view)
        // 112 她：「右滑时候 聊天界面会往下掉」。只认从最右边缘起手、明显往左横着走的划动，
        // 而且这一下不跟上下滚动同时动（见下面），聊天记录就不会被带着跑。
        return start.x > view.bounds.width - KeDrawerEdge.width
            && velocity.x < 0 && abs(velocity.x) > abs(velocity.y) * 1.3
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // 拉设置的那一下不和列表自己的滚动一起动；长按菜单之类照常
        otherGestureRecognizer !== collectionView.panGestureRecognizer
    }
}

/// 112：拉设置抽屉只认屏幕最右边这一条（三个页面都一样）
enum KeDrawerEdge {
    static let width: CGFloat = 32
}
