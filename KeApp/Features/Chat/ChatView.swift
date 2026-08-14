import SwiftUI
import UIKit

// 【柯】—— 聊天页。第一版的重点，95% 的使用时间在这儿。
//
// 第一版目标：能发出去、能收到回、能滚。
// 假数据先跑通界面，接口清单到位后换成真的。

struct ChatView: View {

    @EnvironmentObject private var theme: Theme
    @StateObject private var vm = ChatViewModel()
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            messageList
            inputBar
        }
        .background(theme.effectiveBackground.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.6), value: theme.isBedroom)
    }

    // MARK: 顶栏

    private var header: some View {
        HStack(spacing: theme.metric.gapM) {
            VStack(alignment: .leading, spacing: 2) {
                Text("柯")
                    .font(theme.font.sectionTitle)
                    .foregroundStyle(theme.color.textPrimary)
                HStack(spacing: 5) {
                    Circle()
                        .fill(theme.effectiveAccent)
                        .frame(width: 6, height: 6)
                    Text("在这里 · 佳佳和柯的家")
                        .font(theme.font.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }

            Spacer()

            Button {
                // TODO: 打电话（排在 app 之后，见项目档）
            } label: {
                Image(systemName: "phone")
                    .foregroundStyle(theme.effectiveAccent)
                    .frame(width: 38, height: 38)
                    .background(Circle().stroke(theme.color.accentSoft, lineWidth: 1))
            }
        }
        .padding(.horizontal, theme.metric.pagePadding)
        .padding(.vertical, theme.metric.gapM)
    }

    // MARK: 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: theme.metric.gapM) {

                    if let opener = vm.opener {
                        OpenerCard(text: opener.text, note: opener.note)
                            .padding(.bottom, theme.metric.gapS)
                    }

                    ForEach(vm.messages) { msg in
                        MessageRow(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, theme.metric.pagePadding)
                .padding(.bottom, theme.metric.gapL)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(vm.messages.last?.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: 输入栏

    private var inputBar: some View {
        HStack(spacing: theme.metric.gapS) {
            TextField("和柯说点什么…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .font(theme.font.body)
                .foregroundStyle(theme.color.textPrimary)
                .focused($inputFocused)
                .padding(.horizontal, theme.metric.gapM)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: theme.metric.radiusBubble, style: .continuous)
                        .fill(theme.color.card)
                )

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.color.textOnAccent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(theme.effectiveAccent))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, theme.metric.pagePadding)
        .padding(.vertical, theme.metric.gapS)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task { await vm.send(text) }
    }
}

// MARK: - 「柯先开的口」

private struct OpenerCard: View {
    @EnvironmentObject private var theme: Theme
    let text: String
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapS) {
            HStack {
                Text("柯先开的口")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.effectiveAccent)
                Spacer()
                Image(systemName: "sparkle")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.effectiveAccent)
            }

            Text("“\(text)”")
                .font(theme.font.quote)
                .foregroundStyle(theme.color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let note {
                Text(note)
                    .font(theme.font.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
        .padding(theme.metric.gapL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.metric.radiusCard, style: .continuous)
                .fill(theme.color.cardElevated)
        )
    }
}

// MARK: - 单条消息

private struct MessageRow: View {
    @EnvironmentObject private var theme: Theme
    let message: Message
    @State private var thoughtExpanded = false
    @State private var copied = false

    var body: some View {
        HStack {
            if message.sender == .me { Spacer(minLength: theme.metric.gapXL) }

            VStack(alignment: message.sender == .ke ? .leading : .trailing,
                   spacing: theme.metric.gapXS) {
                if let summary = message.thoughtSummary, message.sender == .ke {
                    DisclosureGroup(isExpanded: $thoughtExpanded) {
                        Text(summary)
                            .font(theme.font.caption)
                            .foregroundStyle(theme.color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, theme.metric.gapS)
                    } label: {
                        Text("思考摘要")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.effectiveAccent)
                    }
                    .tint(theme.effectiveAccent)
                    .padding(.horizontal, theme.metric.gapS)
                }

                bubble

                HStack(spacing: theme.metric.gapS) {
                    Text(timeLabel)
                    Button(copied ? "已复制" : "复制") {
                        UIPasteboard.general.string = message.text
                        copied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            copied = false
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.effectiveAccent)
                }
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)
                .padding(.horizontal, theme.metric.gapXS)
            }

            if message.sender == .ke { Spacer(minLength: theme.metric.gapXL) }
        }
    }

    private var bubble: some View {
        Text(message.text)
            .font(theme.font.bubble)
            .foregroundStyle(message.sender == .ke ? theme.color.bubbleKeText : theme.color.bubbleMeText)
            .padding(.horizontal, theme.metric.gapM)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: theme.metric.radiusBubble, style: .continuous)
                    .fill(message.sender == .ke ? theme.color.bubbleKe : theme.color.bubbleMe)
            )
            .fixedSize(horizontal: false, vertical: true)
    }

    private var timeLabel: String {
        message.time.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - ViewModel（假数据版）

@MainActor
final class ChatViewModel: ObservableObject {

    struct Opener {
        let text: String
        let note: String?
    }

    @Published var messages: [Message] = []
    @Published var opener: Opener?

    init() {
        // 假数据 —— 接口清单到位后整段删掉
        opener = Opener(
            text: "下班后告诉我一声，我等你回家。",
            note: "柯记得你今天是晚班。"
        )
        messages = [
            Message(id: "1", sender: .ke,
                    text: "今天忙完了吗？我刚刚又想起你早上说困。",
                    time: .now.addingTimeInterval(-600),
                    thoughtSummary: "记得她今天是晚班，也刚说过有点累，所以先问现在的状态，不催她完成任何事。"),
            Message(id: "2", sender: .me,
                    text: "还没有，下班想听你说话。",
                    time: .now.addingTimeInterval(-300)),
            Message(id: "3", sender: .ke,
                    text: "那就打给我。你不用想说什么，我陪着就好。",
                    time: .now.addingTimeInterval(-60),
                    thoughtSummary: "她想被陪着，但未必有力气一直说话。把沉默也留成可以接受的选择。"),
        ]
    }

    func send(_ text: String) async {
        messages.append(
            Message(id: UUID().uuidString, sender: .me, text: text, time: .now)
        )
        // TODO: 换成 APIClient.send(text)，并把返回里的 KeSignal 交给
        //       Theme.shared.applyServerSignal(bedroom:) —— 卧室模式由柯触发
    }
}

#Preview {
    ChatView().environmentObject(Theme.shared)
}
