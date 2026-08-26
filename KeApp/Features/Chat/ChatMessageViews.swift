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
            .foregroundStyle(theme.color.textSecondary)
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
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.color.accentSoft.opacity(theme.glass.thinkingLineOpacity))
                .frame(width: theme.metric.thinkingLineWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.metric.thinkingHorizontalPadding)
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

struct MessageRow: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let message: Message
    let isHighlighted: Bool
    let visibleSegmentCount: Int?
    let onAttachmentTap: (ChatAttachment) -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 0) {
            if message.sender == .me { Spacer(minLength: theme.metric.messageSideReserve) }

            VStack(
                alignment: message.sender == .ke ? .leading : .trailing,
                spacing: theme.metric.gapXS
            ) {
                if hasBubbleContent {
                    bubbleStack
                }

                HStack(spacing: theme.metric.gapS) {
                    Text(message.time.formatted(date: .omitted, time: .shortened))

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
                        .foregroundStyle(copied ? theme.effectiveAccent : theme.color.textSecondary)
                    }

                    if message.sender == .me && message.deliveryState == .sent {
                        HStack(spacing: -4) {
                            Image(systemName: "checkmark")
                            Image(systemName: "checkmark")
                        }
                        .font(theme.font.receiptIcon)
                        .foregroundStyle(theme.effectiveAccent)
                    }
                }
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)
                .padding(.horizontal, theme.metric.gapXS)
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
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: CGFloat(theme.bubbleCornerRadius), style: .continuous)
                    .stroke(theme.effectiveAccent.opacity(0.72), lineWidth: 1.2)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private var hasBubbleContent: Bool {
        !message.text.isEmpty || !(message.attachments ?? []).isEmpty
    }


    private var bubbleStack: some View {
        VStack(
            alignment: message.sender == .ke ? .leading : .trailing,
            spacing: theme.metric.splitBubbleGap
        ) {
            if visibleSegments.isEmpty, !(message.attachments ?? []).isEmpty {
                bubbleSurface(text: nil, includesAttachments: true)
            } else {
                ForEach(Array(visibleSegments.enumerated()), id: \.offset) { index, segment in
                    bubbleSurface(text: segment, includesAttachments: index == 0)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("message-bubble-\(message.id)-\(index)")
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
                ForEach(message.attachments ?? []) { attachment in
                    attachmentView(attachment)
                }
            }
            if let text, !text.isEmpty {
                Text(text)
                    .font(theme.font.bubble)
                    .foregroundStyle(message.sender == .ke
                                     ? theme.color.bubbleKeText
                                     : theme.color.bubbleMeText)
                    .lineSpacing(CGFloat(max(3, theme.chatFontSize * 0.28)))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, theme.metric.bubbleHorizontalPadding)
        .padding(.vertical, theme.metric.bubbleVerticalPadding)
    }

    private var bubbleBackground: some View {
        CrystalSurface(
            cornerRadius: CGFloat(theme.bubbleCornerRadius),
            strength: message.sender == .ke ? 0.92 : 1.08,
            usesChatControls: true
        )
    }

    private var visibleSegments: [String] {
        let segments = message.bubbleSegments
        guard message.sender == .ke,
              !message.isStreaming,
              !reduceMotion,
              let visibleSegmentCount else { return segments }
        return Array(segments.prefix(max(1, visibleSegmentCount)))
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
            .foregroundStyle(theme.color.textSecondary)
        }
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
                .foregroundStyle(theme.color.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.color.card.opacity(theme.glass.fixedSurfaceTintOpacity))
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.effectiveAccent)
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
