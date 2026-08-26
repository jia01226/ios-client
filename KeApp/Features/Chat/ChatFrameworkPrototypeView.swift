#if DEBUG
import ExyteChat
import SwiftUI

/// 隔离验证成熟聊天框架是否能承住柯现有的三种高风险交互。
/// 只在 UI 测试传入 `-ui-test-chat-framework-prototype` 时出现，不进入正式 App 路径。
struct ChatFrameworkPrototypeView: View {
    @EnvironmentObject private var theme: Theme
    @State private var messages = Self.makeMessages()
    @State private var expandedThinkingMessageIDs: Set<String> = []

    private static let latestMessageID = "framework-latest"
    private static let latestThinking = "先把她这句话接稳，再决定该怎样回答。"

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppAtmosphere()

            ExyteChat.ChatView(messages: messages) { _ in
                // 原型不碰真实发送链，只验证框架自己的列表与输入交互。
            } messageBuilder: { parameters in
                ChatFrameworkPrototypeMessage(
                    message: parameters.message,
                    thinking: thinking(for: parameters.message.id),
                    isThinkingExpanded: expandedThinkingMessageIDs.contains(parameters.message.id),
                    onThinkingToggle: {
                        toggleThinking(for: parameters.message.id)
                    }
                )
            } inputViewBuilder: { parameters in
                ChatFrameworkPrototypeComposer(parameters: parameters)
            }
            .showDateHeaders(false)
            .showMessageMenuOnLongPress(false)
            .showScrollToBottomButton(false)
            .showNetworkConnectionProblem(false)
            .keyboardDismissMode(.interactive)

            Button {
                appendStreamingChunk()
            } label: {
                Color.clear
                    .frame(
                        width: theme.metric.touchTarget,
                        height: theme.metric.touchTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("继续原型流式回复")
            .accessibilityIdentifier("framework-stream-trigger")
        }
    }

    private func thinking(for messageID: String) -> String? {
        messageID == Self.latestMessageID ? Self.latestThinking : nil
    }

    private func toggleThinking(for messageID: String) {
        if expandedThinkingMessageIDs.contains(messageID) {
            expandedThinkingMessageIDs.remove(messageID)
        } else {
            expandedThinkingMessageIDs.insert(messageID)
        }
    }

    private func appendStreamingChunk() {
        guard let index = messages.firstIndex(where: { $0.id == Self.latestMessageID }) else {
            return
        }
        let current = messages[index]
        let text = String(current.attributedText.characters)
        messages[index].attributedText = AttributedString(
            text + "\n最后一句在流式回复里继续长出来。"
        )
    }

    private static func makeMessages() -> [ExyteChat.Message] {
        let me = ExyteChat.User(
            id: "prototype-me",
            name: "佳佳",
            avatarURL: nil,
            isCurrentUser: true
        )
        let ke = ExyteChat.User(
            id: "prototype-ke",
            name: "柯",
            avatarURL: nil,
            isCurrentUser: false
        )
        let start = Date.now.addingTimeInterval(-1_200)
        var result: [ExyteChat.Message] = (0..<12).map { index in
            ExyteChat.Message(
                id: "framework-history-\(index)",
                user: index.isMultiple(of: 3) ? me : ke,
                createdAt: start.addingTimeInterval(Double(index * 60)),
                text: index.isMultiple(of: 3)
                    ? "前面的消息 \(index + 1)"
                    : "这是一条用来验证滚动位置的历史回复。"
            )
        }
        result.append(
            ExyteChat.Message(
                id: Self.latestMessageID,
                user: ke,
                createdAt: .now,
                text: "这是最新一条原型回复。"
            )
        )
        return result
    }
}

private struct ChatFrameworkPrototypeMessage: View {
    @EnvironmentObject private var theme: Theme
    let message: ExyteChat.Message
    let thinking: String?
    let isThinkingExpanded: Bool
    let onThinkingToggle: () -> Void

    var body: some View {
        HStack {
            if message.user.isCurrentUser { Spacer(minLength: theme.metric.messageSideReserve) }

            VStack(
                alignment: message.user.isCurrentUser ? .trailing : .leading,
                spacing: theme.metric.thinkingBubbleGap
            ) {
                if let thinking {
                    thinkingView(thinking)
                }

                Text(String(message.attributedText.characters))
                    .font(theme.font.bubble)
                    .foregroundStyle(
                        message.user.isCurrentUser
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
            }
            .frame(
                maxWidth: message.user.isCurrentUser ? theme.metric.bubbleMaxWidth : .infinity,
                alignment: message.user.isCurrentUser ? .trailing : .leading
            )

            if !message.user.isCurrentUser { Spacer(minLength: 0) }
        }
        .padding(.horizontal, theme.metric.pagePadding)
    }

    private func thinkingView(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: theme.metric.gapS) {
            Button(action: onThinkingToggle) {
                HStack(spacing: theme.metric.gapS) {
                    Text("Thinking")
                        .font(theme.font.thinking)
                    Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(theme.font.thinkingChevron)
                }
                .foregroundStyle(theme.color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isThinkingExpanded ? "收起原型思考" : "展开原型思考")
            .accessibilityIdentifier("framework-thinking-toggle")

            if isThinkingExpanded {
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
    let parameters: InputViewBuilderParameters

    var body: some View {
        HStack(spacing: theme.metric.gapS) {
            TextField("和柯说点什么…", text: parameters.text, axis: .vertical)
                .lineLimit(1...5)
                .font(theme.font.body)
                .foregroundStyle(theme.color.textPrimary)
                .accessibilityIdentifier("framework-composer")

            Button {
                parameters.inputViewActionClosure(.send)
            } label: {
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
        .background(
            CrystalSurface(
                cornerRadius: theme.metric.radiusComposer
            )
        )
        .padding(.horizontal, theme.metric.pagePadding)
        .padding(.bottom, theme.metric.gapS)
    }
}
#endif
