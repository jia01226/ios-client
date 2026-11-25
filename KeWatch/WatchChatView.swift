import SwiftUI

/// 手表上的聊天：她在右、柯在左，最底下一颗「说话」。点了是系统的输入（语音、手写、表情）。
struct WatchChatView: View {
    @EnvironmentObject private var link: WatchLink
    @State private var messages: [WatchMessage] = []
    @State private var draft = ""
    @State private var waiting = false        // 柯在回
    @State private var note: String?          // 连不上、没登录这类给她看的一句
    @State private var poll: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if !link.paired {
                    notPaired
                } else {
                    chat
                }
            }
            .navigationTitle("柯")
        }
        .task(id: link.baseURL) { await refresh() }
    }

    private var notPaired: some View {
        VStack(spacing: 8) {
            Text("在手机上打开一次柯")
                .font(.headline)
            Text("手机会把登录递过来，手表就能聊了")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("再试一次") { link.askPhone() }
        }
        .padding()
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(messages) { bubble($0).id($0.id) }
                    if waiting {
                        HStack {
                            Text("柯在打字…").font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .id(-1)
                    }
                    if let note {
                        Text(note).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                    }
                    TextFieldLink(prompt: Text("跟柯说…")) {
                        Label("说话", systemImage: "mic.fill")
                            .frame(maxWidth: .infinity)
                    } onSubmit: { text in
                        Task { await send(text) }
                    }
                    .padding(.top, 4)
                    .id(-2)
                }
            }
            .onChange(of: messages) { _, _ in
                withAnimation { proxy.scrollTo(-2, anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo(-2, anchor: .bottom) }
        }
        .refreshable { await refresh() }
    }

    private func bubble(_ m: WatchMessage) -> some View {
        HStack {
            if m.fromHer { Spacer(minLength: 18) }
            Text(m.text)
                .font(.system(size: 15))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(m.fromHer ? Color(red: 0.62, green: 0.20, blue: 0.27) : Color.white.opacity(0.14))
                )
            if !m.fromHer { Spacer(minLength: 18) }
        }
    }

    private var api: WatchAPI? { link.baseURL.map { WatchAPI(baseURL: $0) } }

    private func refresh() async {
        guard let api else { return }
        do {
            messages = try await api.recent()
            note = nil
        } catch WatchAPIError.unauthorized {
            note = "登录过期了，在手机上打开一次柯"
            link.askPhone()
        } catch {
            note = "这会儿连不上，下拉再试试"
        }
    }

    private func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let api else { return }
        let lastID = messages.last?.id ?? 0
        // 先把她这句摆上去，不让她觉得没发出去
        messages.append(WatchMessage(id: Int.max - messages.count, fromHer: true, text: text, createdAt: ""))
        waiting = true
        note = nil
        do {
            try await api.send(text)
        } catch {
            waiting = false
            note = "刚才那句没发出去，再说一次吧"
            messages.removeAll { $0.id >= Int.max - 1000 }
            return
        }
        // 柯想好要几秒到一两分钟：每 3 秒看一眼，等到他在我这句之后的回话
        poll?.cancel()
        poll = Task {
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { return }
                guard let fresh = try? await api.recent() else { continue }
                messages = fresh
                let mine = fresh.last(where: { $0.fromHer && $0.id > lastID })?.id ?? lastID
                if fresh.contains(where: { !$0.fromHer && $0.id > mine }) {
                    // 他可能分几条说，再等一小会儿收齐
                    try? await Task.sleep(for: .seconds(4))
                    if let more = try? await api.recent() { messages = more }
                    break
                }
            }
            waiting = false
        }
    }
}
