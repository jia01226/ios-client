import SwiftUI
import UIKit

struct ThinkingTimelineRow: View {
    @EnvironmentObject private var theme: Theme
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: theme.metric.gapS) {
                Text("Thinking")
                Image(systemName: "chevron.up")
                    .font(theme.font.thinkingChevron)
            }
            .font(theme.font.thinking)
            .foregroundStyle(theme.chatTextSecondary)
                .modifier(ChatLegibility())
            .frame(
                maxWidth: .infinity,
                minHeight: theme.metric.touchTarget,
                alignment: .bottomLeading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看思考")
        .padding(.leading, theme.metric.thinkingLineGap + theme.metric.thinkingLineWidth)
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(theme.color.accentSoft.opacity(theme.glass.thinkingLineOpacity))
                .frame(
                    width: theme.metric.thinkingLineWidth,
                    height: theme.metric.thinkingLineHeight
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.metric.thinkingHorizontalPadding)
    }
}

/// Thinking 与正文之间的轻量工具卡。默认只露出一行状态，点按后才显示详情。
struct ChatToolStatusRow: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let toolRun: ChatToolRun
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if reduceMotion {
                    isExpanded.toggle()
                } else {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: theme.metric.gapS) {
                    statusIcon
                        .frame(width: theme.metric.gapL, height: theme.metric.gapL)

                    VStack(alignment: .leading, spacing: theme.metric.gapXS) {
                        Text(toolRun.title.isEmpty ? "柯正在处理" : toolRun.title)
                            .font(theme.font.caption.weight(.medium))
                            .foregroundStyle(theme.chatTextPrimary)
                            .lineLimit(1)

                        Text(compactStatus)
                            .font(theme.font.caption)
                            .foregroundStyle(theme.chatTextSecondary)
                .modifier(ChatLegibility())
                            .lineLimit(1)
                    }

                    Spacer(minLength: theme.metric.gapS)

                    Image(systemName: "chevron.down")
                        .font(theme.font.disclosureIcon)
                        .foregroundStyle(theme.chatTextSecondary)
                .modifier(ChatLegibility())
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, theme.metric.gapM)
                .frame(minHeight: theme.metric.touchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)

            if isExpanded {
                Rectangle()
                    .fill(theme.color.separator)
                    .frame(height: theme.metric.thinkingLineWidth)
                    .padding(.horizontal, theme.metric.gapM)

                VStack(alignment: .leading, spacing: theme.metric.gapS) {
                    Text(detailText)
                        .font(theme.font.caption)
                        .foregroundStyle(theme.chatTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let scheduledText {
                        Label(scheduledText, systemImage: "clock")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.chatTextSecondary)
                .modifier(ChatLegibility())
                    }

                    if toolRun.state == .failed, toolRun.retryable {
                        Text("可以让柯再试一次")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.chatAccent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.metric.gapM)
                .padding(.top, theme.metric.gapS)
                .padding(.bottom, theme.metric.gapM)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: theme.metric.bubbleMaxWidth)
        .background(
            // 127：这张卡在聊天记录的格子里，跟着滑：不挂实时模糊和影子
            CrystalSurface(
                cornerRadius: theme.metric.radiusChip,
                strength: 0.76,
                usesChatControls: true,
                isStatic: true
            )
        )
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch toolRun.state {
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(theme.chatAccent)
                .accessibilityHidden(true)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.chatAccent)
                .accessibilityHidden(true)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(theme.chatAccent)
                .accessibilityHidden(true)
        case .awaitingApproval:
            Image(systemName: "hand.raised")
                .foregroundStyle(theme.chatAccent)
                .accessibilityHidden(true)
        case .unknown:
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(theme.chatTextSecondary)
                .modifier(ChatLegibility())
                .accessibilityHidden(true)
        }
    }

    private var compactStatus: String {
        switch toolRun.state {
        case .running: return "正在处理"
        case .succeeded: return "已完成"
        case .failed: return "没有完成"
        case .awaitingApproval: return "等你确认"
        case .unknown: return "状态待确认"
        }
    }

    private var detailText: String {
        let detail = toolRun.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty { return detail }
        switch toolRun.state {
        case .running: return "柯正在处理这件事。"
        case .succeeded: return "这件事已经处理好了。"
        case .failed: return "这次没有处理成功。"
        case .awaitingApproval: return "继续之前需要你确认。"
        case .unknown: return "服务器还没有给出完整状态。"
        }
    }

    private var scheduledText: String? {
        guard let value = toolRun.scheduledFor?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return "预计 \(value.replacingOccurrences(of: "T", with: " "))"
    }

    private var accessibilityLabel: String {
        let action = isExpanded ? "点按收起详情" : "点按展开详情"
        return "\(toolRun.title)，\(compactStatus)，\(action)"
    }
}

struct ThinkingSheetView: View {
    @EnvironmentObject private var theme: Theme
    let message: Message
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metric.gapM) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        Text(section)
                            .font(theme.font.thinkingBody)
                            .foregroundStyle(theme.color.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, theme.metric.pagePadding)
                .padding(.vertical, theme.metric.gapM)
            }
            .scrollContentBackground(.hidden)
            .background(theme.color.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Thinking")
                        .font(theme.font.thinking)
                        .foregroundStyle(theme.color.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: onDone)
                        .font(theme.font.body)
                        .foregroundStyle(theme.effectiveAccent)
                }
            }
        }
        .accessibilityIdentifier("thinking-sheet")
    }

    private var sections: [String] {
        [message.thoughtSummary, message.thoughtNote]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
    }
}

/// 111：她隔了一个钟头以上才回，中间一行淡淡的「你消失了 1 小时 36 分」
struct ChatGapRow: View {
    @EnvironmentObject private var theme: Theme
    let minutes: Int

    static func label(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return "你消失了 \(h) 小时" + (m > 0 ? " \(m) 分" : "")
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Text(Self.label(minutes))
                .font(theme.font.caption)
                .foregroundStyle(theme.chatTextSecondary)
                .modifier(ChatLegibility())
                .padding(.horizontal, theme.metric.gapM)
                .padding(.vertical, theme.metric.gapXS)
                .background(Capsule(style: .continuous).fill(theme.chatTextSecondary.opacity(0.10)))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.metric.pagePadding)
        .padding(.vertical, theme.metric.gapXS)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(minutes))
    }
}

struct ChatDateDividerRow: View {
    @EnvironmentObject private var theme: Theme
    let date: Date

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Text(ChatTimelineDate.visibleLabel(for: date))
                .font(theme.font.caption.weight(.medium))
                .foregroundStyle(theme.lockscreenGlass ? theme.chatTextSecondary : theme.color.textOnAccent)
                .modifier(ChatLegibility())
                .padding(.horizontal, theme.metric.gapM)
                .padding(.vertical, theme.metric.gapXS)
                .background(
                    Capsule(style: .continuous)
                        .fill(theme.lockscreenGlass ? .clear : theme.color.textPrimary.opacity(0.92))
                )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.metric.pagePadding)
        .padding(.top, theme.metric.gapS)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ChatTimelineDate.accessibilityLabel(for: date))
    }
}

struct MessageRow: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let message: Message
    let isHighlighted: Bool
    let visibleSegmentCount: Int?
    let onAttachmentTap: (ChatAttachment) -> Void
    var onRecall: (Message) -> Void = { _ in }
    var onSaveQuote: (Message) -> Void = { _ in }
    var isQuoted = false
    /// 112：长按「下个窗带上 / 取消带上」，按整轮钉住
    var onTogglePin: (Message) -> Void = { _ in }
    var isPinned = false
    /// 137：她那句没发稳：长按「重发」「删掉」
    var onResend: (Message) -> Void = { _ in }
    var onDiscard: (Message) -> Void = { _ in }
    /// 121：时间线里柯的每个气泡各占一格，这里说这一格画第几个；时间那一行只跟在最后一个下面。
    /// nil = 整条画在一起（截图测试、预览用）。
    var part: ChatBubblePart? = nil
    @State private var copied = false
    @State private var actionsPresented = false
    @State private var recallAfterDismiss = false
    @State private var quoteAfterDismiss = false
    @State private var pinAfterDismiss = false
    @State private var resendAfterDismiss = false
    @State private var discardAfterDismiss = false
    @State private var notebookText: String?

    var body: some View {
        HStack(spacing: 0) {
            if message.sender == .me { Spacer(minLength: theme.metric.messageSideReserve) }

            VStack(
                alignment: message.sender == .ke ? .leading : .trailing,
                spacing: theme.metric.gapXS
            ) {
                if showsFirstBubble, let diary = message.unlockedDiary {
                    // 120：「爸爸开锁了」画成一张卡：不切气泡、不当文件；点一下直接翻开那一篇
                    DiaryUnlockCard(title: diary.name) { onAttachmentTap(diary) }
                        .accessibilityIdentifier("diary-unlock-\(diary.diaryID ?? 0)")
                } else if showsFirstBubble, let night = message.nightCard {
                    // 128：「夜里日记 · 刚才那一回」：一张卡，就地点评；点卡翻开日记 › 夜里的那一篇
                    NightDiaryCard(message: message, attachment: night) { onAttachmentTap(night) }
                } else if hasBubbleContent {
                    bubbleStack
                }

                if showsFooter {
                    footer
                }
            }
            .frame(
                maxWidth: message.sender == .ke ? .infinity : nil,
                alignment: message.sender == .ke ? .leading : .trailing
            )
        }
        .frame(
            maxWidth: .infinity,
            alignment: message.sender == .ke ? .leading : .trailing
        )
        .onLongPressGesture(minimumDuration: 0.45) {
            guard !message.text.isEmpty || message.canRecall || message.serverID != nil || message.canResend else { return }
            actionsPresented = true
        }
        .popover(isPresented: $actionsPresented) {
            actionsMenu
        }
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: CGFloat(theme.bubbleCornerRadius), style: .continuous)
                    .stroke(theme.chatAccent.opacity(0.72), lineWidth: 1.2)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    /// 时间、送达、复制那一行
    private var footer: some View {
        HStack(spacing: theme.metric.gapS) {
            Text(message.time.formatted(date: .omitted, time: .shortened))
            if isQuoted {
                Image(systemName: "bookmark.fill").accessibilityLabel("已收进语录")
                    .accessibilityIdentifier("message-bookmark-\(message.serverID ?? 0)")
            }
            if isPinned {
                // 轻轻一枚小图钉：这一轮下个窗会带上
                Image(systemName: "pin")
                    .font(.system(size: 9))
                    .opacity(0.7)
                    .accessibilityLabel("下个窗会带上")
            }

            if let label = message.deliveryState.label {
                Text(label)
            }

            if !message.text.isEmpty {
                Button {
                    UIPasteboard.general.string = message.text
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(theme.font.copyIcon)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        // 137：图标还是这么大，能点的地方补到 44×44（多出来的不占排版位置）
                        .modifier(ChatHitSlop(visible: 24, 24, target: theme.metric.touchTarget))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copied ? "已复制" : "复制消息")
                .foregroundStyle(copied ? theme.chatAccent : theme.chatTextSecondary)
            }

            if message.sender == .me && message.deliveryState == .sent {
                HStack(spacing: -4) {
                    Image(systemName: "checkmark")
                    Image(systemName: "checkmark")
                }
                .font(theme.font.receiptIcon)
                .foregroundStyle(theme.chatAccent)
            }
        }
        .font(theme.font.caption)
        .foregroundStyle(theme.chatTextSecondary)
        .modifier(ChatLegibility())
        .padding(.horizontal, theme.metric.gapXS)
    }

    private var actionsMenu: some View {
        VStack(spacing: 0) {
            if message.canResend {
                Button {
                    resendAfterDismiss = true
                    actionsPresented = false
                } label: {
                    Label("重发", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .accessibilityIdentifier("message-action-resend")
                if !message.text.isEmpty { Divider() }
            }
            if !message.text.isEmpty {
                Button {
                    UIPasteboard.general.string = message.text
                    actionsPresented = false
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .accessibilityIdentifier("message-action-copy")
            }
            if message.canRecall {
                if !message.text.isEmpty { Divider() }
                Button(role: .destructive) {
                    recallAfterDismiss = true
                    actionsPresented = false
                } label: {
                    Label("撤回", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }
            if message.canSaveQuote {
                Divider()
                Button {
                    quoteAfterDismiss = true
                    actionsPresented = false
                } label: {
                    Label(isQuoted ? "从语录拿掉" : "收进语录", systemImage: isQuoted ? "bookmark.slash" : "bookmark")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }.accessibilityIdentifier("message-action-quote")
            }
            if message.serverID != nil && !message.isStreaming {
                Divider()
                Button {
                    pinAfterDismiss = true
                    actionsPresented = false
                } label: {
                    Label(isPinned ? "取消带上" : "下个窗带上", systemImage: isPinned ? "pin.slash" : "pin")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }.accessibilityIdentifier("message-action-pin")
            }
            if message.canResend {
                Divider()
                Button(role: .destructive) {
                    discardAfterDismiss = true
                    actionsPresented = false
                } label: {
                    Label("删掉", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .accessibilityIdentifier("message-action-discard")
            }
        }
        .font(theme.font.body)
        .buttonStyle(.plain)
        .frame(width: 180)
        .presentationCompactAdaptation(.popover)
        .onDisappear {
            notebookText = nil
            if quoteAfterDismiss {
                quoteAfterDismiss = false
                onSaveQuote(message)
            }
            if pinAfterDismiss {
                pinAfterDismiss = false
                onTogglePin(message)
            }
            if resendAfterDismiss {
                resendAfterDismiss = false
                onResend(message)
            }
            if discardAfterDismiss {
                discardAfterDismiss = false
                onDiscard(message)
            }
            guard recallAfterDismiss else { return }
            recallAfterDismiss = false
            onRecall(message)
        }
    }

    /// 121：第一个气泡（带附件、日记卡）只画在第一格；时间那一行只画在最后一格
    private var showsFirstBubble: Bool { part?.isFirst ?? true }
    private var showsFooter: Bool { part?.isLast ?? true }
    private var showsAttachments: Bool { showsFirstBubble && !fileAttachments.isEmpty }
    /// 136：图（照片、塔罗牌）不再塞进气泡里，单独一组小图画在气泡上面
    private var imageAttachments: [ChatAttachment] {
        (message.attachments ?? []).filter { $0.isImage && $0.diaryID == nil && $0.nightID == nil }
    }
    private var fileAttachments: [ChatAttachment] {
        (message.attachments ?? []).filter { !($0.isImage && $0.diaryID == nil && $0.nightID == nil) }
    }
    private var showsImages: Bool { showsFirstBubble && !imageAttachments.isEmpty }

    private var hasBubbleContent: Bool {
        !visibleSegments.isEmpty || showsAttachments || showsImages
    }


    private var bubbleStack: some View {
        VStack(
            alignment: message.sender == .ke ? .leading : .trailing,
            spacing: theme.metric.splitBubbleGap
        ) {
            if showsImages {
                let images = imageAttachments
                ChatImageGroup(attachments: images, trailing: message.sender == .me) { index in
                    ChatImageRouter.shared.open(images, at: index)
                }
            }
            if visibleSegments.isEmpty, showsAttachments {
                bubbleSurface(text: nil, includesAttachments: true)
            } else {
                ForEach(visibleSegments) { segment in
                    bubbleSurface(text: segment.text, includesAttachments: segment.id == 0 && showsAttachments)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("message-bubble-\(message.id)-\(segment.id)")
                        .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                            notebookText = segment.text
                            actionsPresented = true
                        })
                }
            }
        }
        .frame(
            maxWidth: message.sender == .ke ? .infinity : nil,
            alignment: message.sender == .ke ? .leading : .trailing
        )
    }

    @ViewBuilder
    private func bubbleSurface(text: String?, includesAttachments: Bool) -> some View {
        if message.sender == .ke && includesAttachments && !fileAttachments.isEmpty {
            bubbleContent(text: text, includesAttachments: includesAttachments)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .background(bubbleBackground)
                .fixedSize(horizontal: false, vertical: true)
        } else if message.sender == .ke {
            // 短句按内容收紧；只要真实排版宽度放不下，就自动改用整行。
            // 不再按中文字数猜宽泡，避免真机字号变化后误判和截断。
            ViewThatFits(in: .horizontal) {
                bubbleContent(text: text, includesAttachments: includesAttachments)
                    .fixedSize(horizontal: true, vertical: true)
                    .background(bubbleBackground)

                bubbleContent(text: text, includesAttachments: includesAttachments)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(bubbleBackground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            bubbleContent(text: text, includesAttachments: includesAttachments)
                .background(bubbleBackground)
                .frame(
                    maxWidth: theme.metric.bubbleMaxWidth,
                    alignment: .trailing
                )
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bubbleContent(text: String?, includesAttachments: Bool) -> some View {
        VStack(
            alignment: message.sender == .ke ? .leading : .trailing,
            spacing: theme.metric.gapS
        ) {
            if includesAttachments {
                ForEach(fileAttachments) { attachment in
                    attachmentView(attachment)
                }
            }
            if let text, !text.isEmpty {
                Text(ChatLinks.linked(text))
                    .font(theme.font.bubble)
                    // 128：字色跟着气泡走（深气泡白字）
                    .foregroundStyle(theme.bubbleInk(bubbleSide))
                    // 链接跟字一个颜色（带下划线），深气泡上不会是一行看不清的蓝
                    .tint(theme.bubbleInk(bubbleSide))
                    .modifier(BubbleTextLegibility())
                    // 128：小红书的链接直接翻到那一篇（见 ChatLinks.open）
                    .environment(\.openURL, OpenURLAction { ChatLinks.open($0) })
                    .lineSpacing(CGFloat(max(3, theme.chatFontSize * 0.28)))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, theme.metric.bubbleHorizontalPadding)
        .padding(.vertical, theme.metric.bubbleVerticalPadding)
    }

    /// 128 她：「消息的边界感太重了，你就做成QQ那个样子吧，然后我自定义颜色」。
    /// 白天、夜里、卧室、照片壁纸都是一整块平的圆角纯色（BubbleFill）：不描边、不加影子、不挂玻璃。
    /// 每个格子不再有实时玻璃，滑动时不用每帧重新采样底下——这也是滑动最后那点开销。
    private var bubbleSide: BubbleSide { message.sender == .me ? .me : .ke }

    private var bubbleBackground: some View {
        BubbleFill(
            color: theme.bubbleFill(bubbleSide),
            density: theme.bubbleFillDensity(bubbleSide),
            cornerRadius: CGFloat(theme.bubbleCornerRadius)
        )
    }

    /// id 是这个气泡在整句里的序号（无障碍标识、附件都按它认）
    private struct ShownSegment: Identifiable {
        let id: Int
        let text: String
    }

    private var visibleSegments: [ShownSegment] {
        if let part {
            // 121：这一格只画自己那一个气泡，字是时间线切好时就定下的那一份
            return part.text.map(ChatTarotTag.strip).flatMap { $0.isEmpty ? nil : [ShownSegment(id: part.index, text: $0)] } ?? []
        }
        let segments = message.bubbleSegments
        let shown: [String]
        if message.sender == .ke, !message.isStreaming, !reduceMotion, let visibleSegmentCount {
            shown = Array(segments.prefix(max(1, visibleSegmentCount)))
        } else {
            shown = segments
        }
        // 136：「[塔罗#123]」是给服务器认的，她这边不显示
        return shown.enumerated().compactMap { item in
            let text = ChatTarotTag.strip(item.element)
            return text.isEmpty ? nil : ShownSegment(id: item.offset, text: text)
        }
    }

    /// 图都画在气泡外面了（ChatImageGroup），气泡里只剩文件
    private func attachmentView(_ attachment: ChatAttachment) -> some View {
        HStack(spacing: theme.metric.gapS) {
            Image(systemName: "doc")
            Text(attachment.name.isEmpty ? "文件" : attachment.name)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .font(theme.font.caption)
        .foregroundStyle(theme.chatTextSecondary)
        .modifier(ChatLegibility())
    }

}

/// 137：小图标、小字按钮看着多大不变，能点的地方往外多出一圈（凑够 44×44）。
/// 先垫开、定好能点的形状、再收回来：多出来的那圈不占排版位置，旁边的东西一点不挪
struct ChatHitSlop: ViewModifier {
    let leading: CGFloat
    let trailing: CGFloat
    let vertical: CGFloat

    init(horizontal: CGFloat, vertical: CGFloat) {
        leading = horizontal
        trailing = horizontal
        self.vertical = vertical
    }

    /// 左右不一样多：挨着别的按钮那一边少伸一点，不抢它的点
    init(leading: CGFloat, trailing: CGFloat, vertical: CGFloat) {
        self.leading = leading
        self.trailing = trailing
        self.vertical = vertical
    }

    /// 看着 width×height 的，补到 target×target
    init(visible width: CGFloat, _ height: CGFloat, target: CGFloat) {
        leading = max(0, (target - width) / 2)
        trailing = leading
        vertical = max(0, (target - height) / 2)
    }

    func body(content: Content) -> some View {
        content
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .padding(.vertical, vertical)
            .contentShape(Rectangle())
            .padding(.leading, -leading)
            .padding(.trailing, -trailing)
            .padding(.vertical, -vertical)
    }
}

/// 120：柯开锁了一篇日记——聊天里一张玻璃小卡：小锁打开、「爸爸开锁了」、标题、「点开看 ›」。
/// 整张都能点（至少 64 点高），点开就是那一篇。
struct DiaryUnlockCard: View {
    @EnvironmentObject private var theme: Theme
    let title: String
    var onOpen: () -> Void
    private var shownTitle: String {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "这一页" : value
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "lock.open")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(Ink.meText)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Ink.meFill))
                VStack(alignment: .leading, spacing: 3) {
                    Text("爸爸开锁了").font(Ink.song(12.5)).foregroundStyle(Ink.secondary)
                    Text(shownTitle).font(Ink.song(17)).foregroundStyle(Ink.primary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("点开看 ›").font(Ink.song(13.5)).foregroundStyle(Ink.accent)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: theme.metric.bubbleMaxWidth, minHeight: 64, alignment: .leading)
            .background(KeGlass(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), minPaper: 0.7))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("爸爸开锁了：\(shownTitle)")
        .accessibilityHint("点开看这篇日记")
        .accessibilityAddTraits(.isButton)
    }
}

/// 109：柯自己逛小红书、把喜欢的发给她。气泡里的链接点一下就能打开（小红书的链接很长，显示成「去小红书看 ›」）。
enum ChatLinks {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func linked(_ text: String) -> AttributedString {
        guard let detector, text.contains("http") || text.contains("xhslink") else { return AttributedString(text) }
        let ns = text as NSString
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return AttributedString(text) }
        var out = AttributedString()
        var cursor = 0
        for m in matches {
            guard let url = m.url, url.scheme?.hasPrefix("http") == true else { continue }
            if m.range.location > cursor {
                out += AttributedString(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            }
            var piece = AttributedString(label(for: url, raw: ns.substring(with: m.range)))
            piece.link = url
            piece.underlineStyle = .single
            out += piece
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length { out += AttributedString(ns.substring(from: cursor)) }
        return out
    }

    /// 128 修：「去小红书看 ›」只打开了小红书 App，没翻到那一篇。
    /// 认出笔记 id（/explore/<id>、/discovery/item/<id>），先叫 App 直接打开那一篇（xhsdiscover://item/<id>）；
    /// 叫不起来（没装、不认）再用 Safari 打开网页版那一篇（带上原来的 xsec_token）。xhslink 短链接照原样打开。
    struct XHSNote: Equatable {
        let id: String
        let token: String?
    }

    static func xhsNote(_ url: URL) -> XHSNote? {
        let host = url.host?.lowercased() ?? ""
        guard host == "xiaohongshu.com" || host.hasSuffix(".xiaohongshu.com") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let id: String?
        if parts.count >= 2, parts[0] == "explore" {
            id = parts[1]
        } else if parts.count >= 3, parts[0] == "discovery", parts[1] == "item" {
            id = parts[2]
        } else {
            id = nil
        }
        guard let id, !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "xsec_token" }?.value
        return XHSNote(id: id, token: token?.isEmpty == true ? nil : token)
    }

    /// 先试 App 里打开，再退回网页；不是小红书笔记就是 nil（照系统默认打开）
    static func xhsTargets(_ url: URL) -> (app: URL, web: URL)? {
        guard let note = xhsNote(url), let app = URL(string: "xhsdiscover://item/\(note.id)") else { return nil }
        var web = URLComponents()
        web.scheme = "https"
        web.host = "www.xiaohongshu.com"
        web.path = "/discovery/item/\(note.id)"
        // token 里有 = 和 -，自己编码：只放过不会被当成分隔符的字符
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        var query: [String] = []
        if let token = note.token, let encoded = token.addingPercentEncoding(withAllowedCharacters: allowed) {
            query.append("xsec_token=\(encoded)")
        }
        query.append("xsec_source=app_share")
        web.percentEncodedQuery = query.joined(separator: "&")
        guard let webURL = web.url else { return nil }
        return (app, webURL)
    }

    /// 气泡里点链接走这里
    @MainActor
    static func open(_ url: URL) -> OpenURLAction.Result {
        guard let targets = xhsTargets(url) else { return .systemAction }
        UIApplication.shared.open(targets.app, options: [:]) { opened in
            guard !opened else { return }
            UIApplication.shared.open(targets.web, options: [:], completionHandler: nil)
        }
        return .handled
    }

    private static func label(for url: URL, raw: String) -> String {
        let host = url.host?.lowercased() ?? ""
        if host.hasSuffix("xiaohongshu.com") || host.hasSuffix("xhslink.com") { return "去小红书看 ›" }
        if host.hasSuffix("x.com") || host.hasSuffix("twitter.com") { return "去 X 看 ›" }
        return raw.count > 40 ? (host.isEmpty ? String(raw.prefix(36)) + "…" : host + " ›") : raw
    }
}
