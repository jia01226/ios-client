import SwiftUI

/// 145：工坊页。顶上选号和模型、额度小字；中间是对话，它干的每一步一行小字；底下输入，干活时变成「停下」。
struct WorkshopView: View {
    @StateObject private var store: WorkshopStore
    var onClose: () -> Void
    @State private var draft = ""
    @State private var confirmNew = false
    @FocusState private var inputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(api: any WorkshopAPI, onClose: @escaping () -> Void) {
        _store = StateObject(wrappedValue: WorkshopStore(api: api))
        self.onClose = onClose
    }

    private let paper = Color(hex: 0xF6F4F0)

    var body: some View {
        VStack(spacing: 0) {
            header
            modelBar
            Rectangle().fill(Ink.line.opacity(0.35)).frame(height: 0.6)
            timeline
            inputBar
        }
        .background(paper.ignoresSafeArea())
        .task { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.load() } }
        }
        .alert("新开一段？", isPresented: $confirmNew) {
            Button("取消", role: .cancel) {}
            Button("新开") { Task { await store.newConversation() } }
        } message: { Text("工坊会忘掉这段说过的，从头带着说明书重新来。上面的记录还留着。") }
    }

    // MARK: 顶上

    private var header: some View {
        HStack {
            Button("完成", action: onClose)
                .font(.system(size: 15))
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            Spacer()
            VStack(spacing: 0) {
                Text("工坊").font(Ink.song(19)).tracking(3)
                Text("Workshop").font(Ink.script(14)).foregroundStyle(Ink.secondary)
            }
            Spacer()
            Button { confirmNew = true } label: {
                Image(systemName: "square.and.pencil").font(.system(size: 16))
                    .frame(width: 44, height: 44)
            }
            .disabled(store.running)
            .accessibilityLabel("新开一段")
        }
        .foregroundStyle(Ink.primary)
        .padding(.horizontal, 12)
    }

    private var modelBar: some View {
        VStack(spacing: 2) {
            Menu {
                ForEach([1, 2, 0], id: \.self) { account in
                    let group = store.choices.filter { $0.account == account }
                    if !group.isEmpty {
                        Section(account == 0 ? "DeepSeek（不能联网搜索）" : "\(account) 号") {
                            ForEach(group) { c in
                                Button {
                                    Task { await store.setModel(c.id) }
                                } label: {
                                    if c.id == store.model { Label(c.label, systemImage: "checkmark") } else { Text(c.label) }
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(store.current?.label ?? "选一个号")
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }
                .font(.system(size: 14))
                .foregroundStyle(Ink.primary)
                .frame(minHeight: 32)
            }
            .accessibilityLabel("工坊用哪个号、哪个模型")
            Text(store.quotaLine)
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(Ink.secondary)
        }
        .padding(.bottom, 8)
    }

    // MARK: 对话

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if store.loaded && store.messages.isEmpty && !store.running {
                        emptyHint
                    }
                    ForEach(store.messages) { m in
                        row(m).id("m\(m.id)")
                    }
                    if store.running {
                        liveRow.id("live")
                    }
                    if let notice = store.notice {
                        Text(notice)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.negative)
                            .frame(maxWidth: .infinity)
                            .onTapGesture { store.notice = nil }
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.count) { _, _ in scrollDown(proxy) }
            .onChange(of: store.live) { _, _ in scrollDown(proxy, animated: false) }
            .onAppear { scrollDown(proxy, animated: false) }
        }
    }

    private func scrollDown(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这里是工坊").font(Ink.song(17))
            Text("跟它说要修什么、查什么，比如「中午 12 点发消息卡住了，查一下」「把荷包的字调大一点」。它在服务器上干活，每一步都会一行行写在这里；关了 App 它也接着干，干完推送告诉你。\n\n它跟柯是两条线：柯看不到这里的细节，只收到一句进度。")
                .font(.system(size: 13))
                .foregroundStyle(Ink.secondary)
        }
        .padding(.top, 30)
    }

    @ViewBuilder private func row(_ m: WorkshopMessage) -> some View {
        switch m.role {
        case "user":
            VStack(alignment: .trailing, spacing: 3) {
                if m.origin == "ke" {
                    Text("柯转来的单子").font(.system(size: 10)).foregroundStyle(Ink.keText)
                }
                Text(m.content)
                    .font(.system(size: 15))
                    .foregroundStyle(Ink.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(m.origin == "ke" ? Ink.keFill : Ink.meFill))
                if m.status == "queued" {
                    Text("排着队").font(.system(size: 10)).foregroundStyle(Ink.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
        case "divider":
            Text("—— \(m.content) ——")
                .font(.system(size: 11)).foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity)
        default:
            VStack(alignment: .leading, spacing: 6) {
                if m.trace.isEmpty {
                    prose(m.content)
                } else {
                    ForEach(Array(m.trace.enumerated()), id: \.offset) { _, item in
                        if let t = item.t {
                            prose(t)
                        } else if let tool = item.tool {
                            toolLine(tool, brief: item.brief ?? "", error: item.error)
                        }
                    }
                }
                if !m.to_ke.isEmpty {
                    Label("已告诉柯：\(m.to_ke)", systemImage: "arrowshape.turn.up.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.keText)
                        .padding(.top, 2)
                }
                if m.status == "error" || m.status == "stopped" {
                    Text(m.status == "stopped" ? "停下了" : "这轮出错停了")
                        .font(.system(size: 11)).foregroundStyle(Ink.negative)
                }
            }
            .padding(.trailing, 12)
        }
    }

    private var liveRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.live) { item in
                if let t = item.text {
                    prose(t)
                } else if let tool = item.tool {
                    toolLine(tool, brief: item.brief ?? "", error: item.error)
                }
            }
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(store.live.isEmpty ? "开工了…" : "还在干…")
                    .font(.system(size: 11)).foregroundStyle(Ink.secondary)
            }
        }
        .padding(.trailing, 12)
    }

    private func prose(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attributed = (try? AttributedString(
            markdown: trimmed,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(trimmed)
        return Text(attributed)
            .font(.system(size: 15))
            .foregroundStyle(Ink.primary)
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toolLine(_ tool: String, brief: String, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: WorkshopToolName.icon(tool)).font(.system(size: 10)).frame(width: 14)
                Text(WorkshopToolName.label(tool)).fontWeight(.medium)
                Text(brief).lineLimit(2)
            }
            if let error, !error.isEmpty {
                Text("没成：" + error).lineLimit(3).foregroundStyle(Ink.negative).padding(.leading, 20)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Ink.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 底下

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(store.running ? "它在干活，也可以先打下一句" : "要修什么、查什么", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .font(.system(size: 15))
                .focused($inputFocused)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.92)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Ink.line.opacity(0.45), lineWidth: 0.7))
            if store.running && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { Task { await store.stop() } } label: {
                    Image(systemName: "stop.circle").font(.system(size: 28))
                        .frame(width: 44, height: 44)
                }
                .foregroundStyle(Ink.negative)
                .accessibilityLabel("停下")
            } else {
                Button {
                    let text = draft
                    Task { if await store.send(text) { draft = "" } }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 28))
                        .frame(width: 44, height: 44)
                }
                .foregroundStyle(Ink.accent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.sending)
                .accessibilityLabel(store.running ? "排上下一句" : "发给工坊")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(paper)
        .overlay(alignment: .top) { Rectangle().fill(Ink.line.opacity(0.3)).frame(height: 0.5) }
    }
}
