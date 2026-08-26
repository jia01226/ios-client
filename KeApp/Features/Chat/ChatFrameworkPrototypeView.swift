#if DEBUG
import ChatLayout
import SwiftUI
import UIKit

/// 隔离验证 ChatLayout 能否承住柯现有的高风险交互。
/// 只在 UI 测试传入 `-ui-test-chat-framework-prototype` 时出现，不进入正式 App 路径。
struct ChatFrameworkPrototypeView: View {
    @EnvironmentObject private var theme: Theme
    @State private var messages = ChatFrameworkPrototypeMessage.makeMessages()
    @State private var composerText = ""

    private static let latestMessageID = "framework-latest"

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppAtmosphere()

            VStack(spacing: 0) {
                ChatLayoutPrototypeTimeline(
                    messages: messages,
                    onThinkingToggle: toggleThinking
                )

                ChatFrameworkPrototypeComposer(text: $composerText)
            }

            Button(action: appendStreamingChunk) {
                Color.clear
                    .frame(width: theme.metric.touchTarget, height: theme.metric.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("继续原型流式回复")
            .accessibilityIdentifier("framework-stream-trigger")
        }
    }

    private func toggleThinking(_ messageID: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].isThinkingExpanded.toggle()
    }

    private func appendStreamingChunk() {
        guard let index = messages.firstIndex(where: { $0.id == Self.latestMessageID }) else { return }
        messages[index].text += "\n最后一句在流式回复里继续长出来。"
    }
}

private struct ChatFrameworkPrototypeMessage: Identifiable, Equatable {
    let id: String
    let isCurrentUser: Bool
    var text: String
    let thinking: String?
    var isThinkingExpanded = false

    static func makeMessages() -> [Self] {
        var result = (0..<12).map { index in
            Self(
                id: "framework-history-\(index)",
                isCurrentUser: index.isMultiple(of: 3),
                text: index.isMultiple(of: 3)
                    ? "前面的消息 \(index + 1)"
                    : "这是一条用来验证滚动位置的历史回复。",
                thinking: nil
            )
        }
        result.append(
            Self(
                id: "framework-latest",
                isCurrentUser: false,
                text: "这是最新一条原型回复。",
                thinking: "先把她这句话接稳，再决定该怎样回答。"
            )
        )
        return result
    }
}

private struct ChatLayoutPrototypeTimeline: UIViewControllerRepresentable {
    let messages: [ChatFrameworkPrototypeMessage]
    let onThinkingToggle: (String) -> Void

    func makeUIViewController(context: Context) -> ChatLayoutPrototypeController {
        ChatLayoutPrototypeController(messages: messages, onThinkingToggle: onThinkingToggle)
    }

    func updateUIViewController(
        _ controller: ChatLayoutPrototypeController,
        context: Context
    ) {
        controller.update(messages: messages, onThinkingToggle: onThinkingToggle)
    }
}

private final class ChatLayoutPrototypeController: UIViewController,
    UICollectionViewDataSource,
    ChatLayoutDelegate
{
    private typealias Cell = UICollectionViewCell

    private let chatLayout = CollectionViewChatLayout()
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: chatLayout
    )
    private var messages: [ChatFrameworkPrototypeMessage]
    private var onThinkingToggle: (String) -> Void
    private var didScrollToLatest = false

    init(
        messages: [ChatFrameworkPrototypeMessage],
        onThinkingToggle: @escaping (String) -> Void
    ) {
        self.messages = messages
        self.onThinkingToggle = onThinkingToggle
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        chatLayout.delegate = self
        chatLayout.settings.interItemSpacing = 8
        chatLayout.settings.additionalInsets = .zero
        chatLayout.keepContentOffsetAtBottomOnBatchUpdates = true
        chatLayout.keepContentAtBottomOfVisibleArea = true
        chatLayout.processOnlyVisibleItemsOnAnimatedBatchUpdates = false
        chatLayout.supportSelfSizingInvalidation = true

        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.selfSizingInvalidation = .enabled
        collectionView.dataSource = self
        collectionView.register(Cell.self, forCellWithReuseIdentifier: "ChatLayoutPrototypeCell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didScrollToLatest, !messages.isEmpty else { return }
        didScrollToLatest = true
        collectionView.scrollToItem(
            at: IndexPath(item: messages.count - 1, section: 0),
            at: .bottom,
            animated: false
        )
    }

    func update(
        messages newMessages: [ChatFrameworkPrototypeMessage],
        onThinkingToggle: @escaping (String) -> Void
    ) {
        self.onThinkingToggle = onThinkingToggle
        guard newMessages != messages else { return }

        let oldMessages = messages
        let changedIndexes = newMessages.indices.filter { index in
            oldMessages.indices.contains(index) && oldMessages[index] != newMessages[index]
        }
        messages = newMessages

        guard oldMessages.count == newMessages.count, !changedIndexes.isEmpty else {
            collectionView.reloadData()
            return
        }

        let shouldKeepMessageTop = changedIndexes.contains { index in
            let old = oldMessages[index]
            let new = newMessages[index]
            return (!old.isThinkingExpanded && new.isThinkingExpanded)
                || (old.isThinkingExpanded && new.isThinkingExpanded && old.text != new.text)
        }
        let anchorIndexPath = IndexPath(item: changedIndexes.last ?? 0, section: 0)
        let anchorY = shouldKeepMessageTop
            ? collectionView.layoutAttributesForItem(at: anchorIndexPath).map {
                $0.frame.minY - collectionView.contentOffset.y
            }
            : nil

        collectionView.performBatchUpdates {
            collectionView.reloadItems(
                at: changedIndexes.map { IndexPath(item: $0, section: 0) }
            )
        } completion: { [weak self] _ in
            guard let self, let anchorY else { return }
            self.collectionView.layoutIfNeeded()
            guard let attributes = self.collectionView.layoutAttributesForItem(at: anchorIndexPath) else {
                return
            }
            let currentY = attributes.frame.minY - self.collectionView.contentOffset.y
            self.collectionView.contentOffset.y += currentY - anchorY
        }
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        messages.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "ChatLayoutPrototypeCell",
            for: indexPath
        )
        let message = messages[indexPath.item]
        cell.backgroundColor = .clear
        cell.contentConfiguration = UIHostingConfiguration {
            ChatFrameworkPrototypeMessageView(
                message: message,
                onThinkingToggle: { [weak self] in
                    self?.onThinkingToggle(message.id)
                }
            )
            .environmentObject(Theme.shared)
        }
        .margins(.all, 0)
        return cell
    }
}

private struct ChatFrameworkPrototypeMessageView: View {
    @EnvironmentObject private var theme: Theme
    let message: ChatFrameworkPrototypeMessage
    let onThinkingToggle: () -> Void

    var body: some View {
        HStack {
            if message.isCurrentUser { Spacer(minLength: theme.metric.messageSideReserve) }

            VStack(
                alignment: message.isCurrentUser ? .trailing : .leading,
                spacing: theme.metric.thinkingBubbleGap
            ) {
                if let thinking = message.thinking {
                    thinkingView(thinking)
                }

                Text(message.text)
                    .font(theme.font.bubble)
                    .foregroundStyle(
                        message.isCurrentUser
                            ? theme.color.bubbleMeText
                            : theme.color.bubbleKeText
                    )
                    .lineSpacing(theme.metric.gapXS)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, theme.metric.bubbleHorizontalPadding)
                    .padding(.vertical, theme.metric.bubbleVerticalPadding)
                    .background(
                        CrystalSurface(
                            cornerRadius: CGFloat(theme.bubbleCornerRadius),
                            usesChatControls: true
                        )
                    )
                    .accessibilityIdentifier(
                        message.id == "framework-latest" ? "framework-latest-reply" : ""
                    )
            }
            .frame(
                maxWidth: message.isCurrentUser ? theme.metric.bubbleMaxWidth : .infinity,
                alignment: message.isCurrentUser ? .trailing : .leading
            )

            if !message.isCurrentUser { Spacer(minLength: 0) }
        }
        .padding(.horizontal, theme.metric.pagePadding)
    }

    private func thinkingView(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: theme.metric.gapS) {
            Button(action: onThinkingToggle) {
                HStack(spacing: theme.metric.gapS) {
                    Text("Thinking")
                        .font(theme.font.thinking)
                    Image(systemName: message.isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(theme.font.thinkingChevron)
                }
                .foregroundStyle(theme.color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(message.isThinkingExpanded ? "收起原型思考" : "展开原型思考")
            .accessibilityIdentifier("framework-thinking-toggle")

            if message.isThinkingExpanded {
                Text(thinking)
                    .font(theme.font.thinkingBody)
                    .foregroundStyle(theme.color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("framework-thinking-body")
            }
        }
        .padding(.leading, theme.metric.thinkingLineGap + theme.metric.thinkingLineWidth)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.color.accentSoft.opacity(theme.glass.thinkingLineOpacity))
                .frame(width: theme.metric.thinkingLineWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.metric.thinkingHorizontalPadding)
    }
}

private struct ChatFrameworkPrototypeComposer: View {
    @EnvironmentObject private var theme: Theme
    @Binding var text: String

    var body: some View {
        HStack(spacing: theme.metric.gapS) {
            TextField("和柯说点什么…", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .font(theme.font.body)
                .foregroundStyle(theme.color.textPrimary)
                .accessibilityIdentifier("framework-composer")

            Button(action: {}) {
                Image(systemName: "arrow.up")
                    .font(theme.font.sendIcon)
                    .foregroundStyle(theme.color.textOnAccent)
                    .frame(width: theme.metric.touchTarget, height: theme.metric.touchTarget)
                    .background(Circle().fill(theme.effectiveAccent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("发送原型消息")
        }
        .padding(.horizontal, theme.metric.pagePadding)
        .padding(.vertical, theme.metric.gapS)
        .background(CrystalSurface(cornerRadius: theme.metric.radiusComposer))
        .padding(.horizontal, theme.metric.pagePadding)
        .padding(.bottom, theme.metric.gapS)
    }
}
#endif
