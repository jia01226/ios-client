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
    /// 121：时间线里柯的每个气泡各占一格，这里说这一格画第几个；时间那一行只跟在最后一个下面。
    /// nil = 整条画在一起（截图测试、预览用）。
    var part: ChatBubblePart? = nil
    @State private var copied = false
    @State private var actionsPresented = false
    @State private var recallAfterDismiss = false
    @State private var quoteAfterDismiss = false
    @State private var pinAfterDismiss = false
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
            guard !message.text.isEmpty || message.canRecall || message.serverID != nil else { return }
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
            guard recallAfterDismiss else { return }
            recallAfterDismiss = false
            onRecall(message)
        }
    }

    /// 121：第一个气泡（带附件、日记卡）只画在第一格；时间那一行只画在最后一格
    private var showsFirstBubble: Bool { part?.isFirst ?? true }
    private var showsFooter: Bool { part?.isLast ?? true }
    private var showsAttachments: Bool { showsFirstBubble && !(message.attachments ?? []).isEmpty }

    private var hasBubbleContent: Bool {
        !visibleSegments.isEmpty || showsAttachments
    }


    private var bubbleStack: some View {
        VStack(
            alignment: message.sender == .ke ? .leading : .trailing,
            spacing: theme.metric.splitBubbleGap
        ) {
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
        if message.sender == .ke && !(message.attachments ?? []).isEmpty {
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
                if isTarotCardMessage {
                    HStack(alignment: .top, spacing: theme.metric.gapS) {
                        ForEach(message.attachments ?? []) { attachment in
                            tarotCardView(attachment)
                        }
                    }
                } else {
                    ForEach(message.attachments ?? []) { attachment in
                        attachmentView(attachment)
                    }
                }
            }
            if let text, !text.isEmpty {
                Text(ChatLinks.linked(text))
                    .font(theme.font.bubble)
                    .foregroundStyle(message.sender == .ke
                                     ? theme.chatBubbleKeText
                                     : theme.chatBubbleMeText)
                    .modifier(ChatLegibility())
                    .lineSpacing(CGFloat(max(3, theme.chatFontSize * 0.28)))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, theme.metric.bubbleHorizontalPadding)
        .padding(.vertical, theme.metric.bubbleVerticalPadding)
    }

    /// 86：她要「玻璃质感的气泡」。iOS 26 用系统 Liquid Glass（最透的 .clear，按下会亮一下、轻轻弹），
    /// 染色仍跟「气泡透明度」滑杆走；iOS 26 以下保留原来的模糊 + 染色。
    /// 127：白天（不在卧室、没用照片壁纸）的气泡改成她在话笺里挑的颜色 × 浓度，一块静止的纯色：
    /// 每个格子不再挂实时玻璃，滑动时不用每帧重新采样底下。夜里、卧室、照片壁纸还走原来的玻璃。
    private var usesPlainBubble: Bool {
        theme.skin == .day && !theme.isBedroom && !theme.lockscreenGlass
    }

    @ViewBuilder
    private var legacyBubbleFill: some View {
        let fillScale: Double = message.sender == .ke ? 36
            : (theme.skin == .day && !theme.isBedroom ? 80 : 13)
        let tint = (message.sender == .me ? theme.color.bubbleMe : theme.color.bubbleKe)
            .opacity(min(1, theme.bubbleOpacity * fillScale))
        if #available(iOS 26.0, *) {
            // 87：玻璃要透出来，染色得淡。默认（滑杆 1.2%）她的约 30%、柯的约 15%，拉满也不超过 60%。
            let glassScale: Double = message.sender == .ke ? 12 : 25
            let glassTint = (message.sender == .me ? theme.color.bubbleMe : theme.color.bubbleKe)
                .opacity(min(0.6, theme.bubbleOpacity * glassScale))
            Color.clear.glassEffect(
                .clear.tint(glassTint).interactive(),
                in: .rect(cornerRadius: CGFloat(theme.bubbleCornerRadius))
            )
        } else {
            ZStack {
                BackdropBlur(
                    intensity: theme.glassBlur / theme.glass.maximumBlurValue,
                    dark: theme.skin == .night || theme.isBedroom
                )
                tint
            }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if usesPlainBubble {
            let side: BubbleSide = message.sender == .me ? .me : .ke
            BubbleFill(
                color: Color(hex: theme.bubbleHex(side)),
                density: theme.bubbleDensity(side),
                ink: theme.chatBubbleKeText,
                cornerRadius: CGFloat(theme.bubbleCornerRadius)
            )
        } else {
            legacyBubbleFill
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(theme.bubbleCornerRadius), style: .continuous))
                .overlay {
                    if message.sender == .ke && !theme.lockscreenGlass {
                        RoundedRectangle(cornerRadius: CGFloat(theme.bubbleCornerRadius), style: .continuous)
                            .strokeBorder(theme.chatBubbleKeText.opacity(0.10), lineWidth: 0.75)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    /// id 是这个气泡在整句里的序号（无障碍标识、附件都按它认）
    private struct ShownSegment: Identifiable {
        let id: Int
        let text: String
    }

    private var visibleSegments: [ShownSegment] {
        if let part {
            // 121：这一格只画自己那一个气泡，字是时间线切好时就定下的那一份
            return part.text.map { [ShownSegment(id: part.index, text: $0)] } ?? []
        }
        let segments = message.bubbleSegments
        let shown: [String]
        if message.sender == .ke, !message.isStreaming, !reduceMotion, let visibleSegmentCount {
            shown = Array(segments.prefix(max(1, visibleSegmentCount)))
        } else {
            shown = segments
        }
        return shown.enumerated().map { ShownSegment(id: $0.offset, text: $0.element) }
    }

    /// 柯自己抽的牌：三张以内、都是图、名字带正逆位。整张显示，不裁切，逆位倒着。
    private var isTarotCardMessage: Bool {
        let items = message.attachments ?? []
        return message.sender == .ke && !items.isEmpty && items.count <= 3
            && items.allSatisfy { $0.isImage && ($0.name.hasSuffix("·正位") || $0.name.hasSuffix("·逆位")) }
    }

    private func tarotCardView(_ attachment: ChatAttachment) -> some View {
        Button {
            onAttachmentTap(attachment)
        } label: {
            VStack(spacing: 4) {
                AuthenticatedAttachmentImage(attachment: attachment, contentMode: .fit)
                    .aspectRatio(0.58, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .rotationEffect(.degrees(attachment.name.hasSuffix("·逆位") ? 180 : 0))
                Text(attachment.name)
                    .font(theme.font.caption)
                    .foregroundStyle(theme.chatTextSecondary)
                .modifier(ChatLegibility())
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开图片 \(attachment.name)")
    }

    @ViewBuilder
    private func attachmentView(_ attachment: ChatAttachment) -> some View {
        if attachment.isImage {
            Button {
                onAttachmentTap(attachment)
            } label: {
                AuthenticatedAttachmentImage(
                    attachment: attachment,
                    contentMode: .fill
                )
                .frame(maxWidth: .infinity)
                .frame(height: theme.metric.messageImageHeight)
                .clipShape(RoundedRectangle(
                    cornerRadius: theme.metric.radiusChip,
                    style: .continuous
                ))
                .contentShape(RoundedRectangle(
                    cornerRadius: theme.metric.radiusChip,
                    style: .continuous
                ))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开图片 \(attachment.name.isEmpty ? "预览" : attachment.name)")
        } else {
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

private struct AuthenticatedAttachmentImage: View {
    @EnvironmentObject private var theme: Theme
    let attachment: ChatAttachment
    let contentMode: ContentMode
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if didFail {
                VStack(spacing: theme.metric.gapS) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(theme.font.attachmentIcon)
                    Text("图片没有加载出来")
                        .font(theme.font.caption)
                }
                .foregroundStyle(theme.chatTextSecondary)
                .modifier(ChatLegibility())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.color.card.opacity(theme.glass.fixedSurfaceTintOpacity))
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.chatAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: attachment.url) {
            image = nil
            didFail = false
            do {
                let data = try await APIClient.shared.fetchAttachmentData(at: attachment.url)
                guard let loaded = UIImage(data: data) else {
                    didFail = true
                    return
                }
                image = loaded
            } catch is CancellationError {
                return
            } catch {
                didFail = true
            }
        }
    }
}

struct AttachmentImageViewer: View {
    @EnvironmentObject private var theme: Theme
    let attachment: ChatAttachment
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            theme.color.glassShadow
                .ignoresSafeArea()

            AuthenticatedAttachmentImage(
                attachment: attachment,
                contentMode: .fit
            )
            .padding(theme.metric.pagePadding)

            VStack {
                HStack {
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(theme.font.composerIcon)
                            .foregroundStyle(theme.color.textOnAccent)
                            .frame(
                                width: theme.metric.touchTarget,
                                height: theme.metric.touchTarget
                            )
                            .background(CrystalSurface(
                                cornerRadius: theme.metric.radiusChip,
                                strength: 1.1,
                                usesChatControls: true
                            ))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭图片")
                }
                Spacer()
            }
            .padding(theme.metric.pagePadding)
        }
        .statusBarHidden()
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

    private static func label(for url: URL, raw: String) -> String {
        let host = url.host?.lowercased() ?? ""
        if host.hasSuffix("xiaohongshu.com") || host.hasSuffix("xhslink.com") { return "去小红书看 ›" }
        if host.hasSuffix("x.com") || host.hasSuffix("twitter.com") { return "去 X 看 ›" }
        return raw.count > 40 ? (host.isEmpty ? String(raw.prefix(36)) + "…" : host + " ›") : raw
    }
}
