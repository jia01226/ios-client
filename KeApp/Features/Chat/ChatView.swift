import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm = ChatViewModel()
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        Group {
            switch vm.phase {
            case .checking:
                checkingView
            case .needsLogin:
                LoginView(vm: vm)
            case .ready:
                chatContent
            case let .unavailable(message):
                unavailableView(message)
            }
        }
        .background(theme.effectiveBackground.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.6), value: theme.isBedroom)
        .task { await vm.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await vm.resumeFromForeground() }
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            header
            if let status = vm.statusText {
                StatusBanner(text: status)
                    .padding(.horizontal, theme.metric.pagePadding)
                    .padding(.bottom, theme.metric.gapS)
            }
            messageList
            inputBar
        }
    }

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
                    Text(vm.isShowingCachedMessages ? "离线记录 · 接回后会自动更新" : "在这里 · 佳佳和柯的家")
                        .font(theme.font.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }

            Spacer()

            Button {
                // 打电话排在真实聊天之后；入口先保留，不做假功能。
            } label: {
                Image(systemName: "phone")
                    .foregroundStyle(theme.effectiveAccent)
                    .frame(width: 38, height: 38)
                    .background(Circle().stroke(theme.color.accentSoft, lineWidth: 1))
            }
            .accessibilityLabel("打电话，后续开放")
        }
        .padding(.horizontal, theme.metric.pagePadding)
        .padding(.vertical, theme.metric.gapM)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: theme.metric.gapM) {
                    if vm.messages.isEmpty {
                        Text("这里还没有聊天记录。\n想说什么，就从下面开始。")
                            .font(theme.font.body)
                            .foregroundStyle(theme.color.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 80)
                    }

                    ForEach(vm.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(.horizontal, theme.metric.pagePadding)
                .padding(.bottom, theme.metric.gapL)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.count) { _, _ in
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: vm.streamRevision) { _, _ in
                scrollToBottom(proxy, animated: false)
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        }
    }

    private var inputBar: some View {
        HStack(spacing: theme.metric.gapS) {
            TextField("和柯说点什么…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .font(theme.font.body)
                .foregroundStyle(theme.color.textPrimary)
                .focused($inputFocused)
                .disabled(vm.isSending)
                .padding(.horizontal, theme.metric.gapM)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: theme.metric.radiusBubble, style: .continuous)
                        .fill(theme.color.card)
                )

            Button { send() } label: {
                Group {
                    if vm.isSending {
                        ProgressView()
                            .tint(theme.color.textOnAccent)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(theme.color.textOnAccent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(theme.effectiveAccent))
            }
            .disabled(trimmedDraft.isEmpty || vm.isSending)
            .opacity(trimmedDraft.isEmpty || vm.isSending ? 0.45 : 1)
        }
        .padding(.horizontal, theme.metric.pagePadding)
        .padding(.vertical, theme.metric.gapS)
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() {
        let text = trimmedDraft
        guard !text.isEmpty, !vm.isSending else { return }
        draft = ""
        Task { await vm.send(text) }
    }

    private var checkingView: some View {
        VStack(spacing: theme.metric.gapM) {
            ProgressView()
                .tint(theme.effectiveAccent)
            Text("正在接回聊天记录…")
                .font(theme.font.body)
                .foregroundStyle(theme.color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableView(_ message: String) -> some View {
        VStack(spacing: theme.metric.gapM) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(theme.effectiveAccent)
            Text(message)
                .font(theme.font.body)
                .foregroundStyle(theme.color.textSecondary)
                .multilineTextAlignment(.center)
            Button("再试一次") {
                Task { await vm.retryBootstrap() }
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.effectiveAccent)
        }
        .padding(theme.metric.gapXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LoginView: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var vm: ChatViewModel
    @State private var passcode = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metric.gapL) {
            Spacer()

            Text("回家")
                .font(theme.font.pageTitle)
                .foregroundStyle(theme.color.textPrimary)

            Text("输入和网页端相同的口令。口令不会保存在手机里；登录成功后只保存服务器签发的登录 Cookie。")
                .font(theme.font.body)
                .foregroundStyle(theme.color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("口令", text: $passcode)
                .textContentType(.password)
                .focused($focused)
                .submitLabel(.go)
                .onSubmit(login)
                .padding(.horizontal, theme.metric.gapM)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: theme.metric.radiusBubble, style: .continuous)
                        .fill(theme.color.card)
                )

            if let error = vm.loginError {
                Text(error)
                    .font(theme.font.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }

            Button(action: login) {
                HStack {
                    Spacer()
                    if vm.isLoggingIn {
                        ProgressView().tint(theme.color.textOnAccent)
                    } else {
                        Text("进去")
                            .font(theme.font.sectionTitle)
                    }
                    Spacer()
                }
                .foregroundStyle(theme.color.textOnAccent)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: theme.metric.radiusBubble, style: .continuous)
                        .fill(theme.effectiveAccent)
                )
            }
            .disabled(passcode.isEmpty || vm.isLoggingIn)
            .opacity(passcode.isEmpty || vm.isLoggingIn ? 0.5 : 1)

            Spacer()
            Spacer()
        }
        .padding(theme.metric.pagePadding)
        .onAppear { focused = true }
    }

    private func login() {
        guard !passcode.isEmpty, !vm.isLoggingIn else { return }
        let value = passcode
        passcode = ""
        Task { await vm.login(passcode: value) }
    }
}

private struct StatusBanner: View {
    @EnvironmentObject private var theme: Theme
    let text: String

    var body: some View {
        HStack(spacing: theme.metric.gapS) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.effectiveAccent)
            Text(text)
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.metric.gapM)
        .padding(.vertical, theme.metric.gapS)
        .background(
            RoundedRectangle(cornerRadius: theme.metric.radiusChip, style: .continuous)
                .fill(theme.color.card)
        )
    }
}

private struct MessageRow: View {
    @EnvironmentObject private var theme: Theme
    let message: Message
    @State private var thoughtChoice: Bool?
    @State private var copied = false

    var body: some View {
        HStack {
            if message.sender == .me { Spacer(minLength: theme.metric.gapXL) }

            VStack(
                alignment: message.sender == .ke ? .leading : .trailing,
                spacing: theme.metric.gapXS
            ) {
                if let summary = message.thoughtSummary,
                   !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   message.sender == .ke {
                    thoughtCard(summary)
                }

                bubble

                HStack(spacing: theme.metric.gapS) {
                    Text(message.time.formatted(date: .omitted, time: .shortened))

                    if let label = message.deliveryState.label {
                        Text(label)
                    }

                    if !message.text.isEmpty {
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
                }
                .font(theme.font.caption)
                .foregroundStyle(theme.color.textSecondary)
                .padding(.horizontal, theme.metric.gapXS)
            }

            if message.sender == .ke { Spacer(minLength: theme.metric.gapXL) }
        }
    }

    private func thoughtCard(_ summary: String) -> some View {
        let expanded = thoughtChoice ?? message.isStreaming
        return VStack(alignment: .leading, spacing: theme.metric.gapS) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    thoughtChoice = !expanded
                }
            } label: {
                HStack(spacing: theme.metric.gapS) {
                    Image(systemName: "sparkles")
                    Text(message.isStreaming ? "正在想" : "思考摘要")
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(theme.font.caption)
                .foregroundStyle(theme.effectiveAccent)
            }
            .buttonStyle(.plain)

            if expanded {
                Group {
                    if message.isStreaming {
                        ScrollView {
                            thoughtText(summary)
                        }
                        .frame(maxHeight: 118)
                    } else {
                        thoughtText(summary)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(theme.metric.gapS)
        .background(
            RoundedRectangle(cornerRadius: theme.metric.radiusChip, style: .continuous)
                .fill(theme.color.cardElevated)
        )
    }

    private func thoughtText(_ summary: String) -> some View {
        Text(summary)
            .font(theme.font.caption)
            .foregroundStyle(theme.color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var bubble: some View {
        Text(message.text.isEmpty && message.isStreaming ? "…" : message.text)
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
}

@MainActor
final class ChatViewModel: ObservableObject {
    enum Phase: Equatable {
        case checking
        case needsLogin
        case ready
        case unavailable(String)
    }

    @Published var phase: Phase = .checking
    @Published var messages: [Message] = []
    @Published var statusText: String?
    @Published var loginError: String?
    @Published var isLoggingIn = false
    @Published var isSending = false
    @Published var isShowingCachedMessages = false
    @Published var streamRevision = 0

    private let api = APIClient.shared
    private let cache = ChatCache.shared
    private var sessionID: Int?
    private var didBootstrap = false
    private var activeJobID: String?
    private var recoveringJobID: String?

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        await connect()
    }

    func retryBootstrap() async {
        phase = .checking
        await connect()
    }

    func login(passcode: String) async {
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }

        do {
            try await api.login(passcode: passcode)
            let id = try await api.activeSessionID()
            sessionID = id
            phase = .ready
            await loadCache(sessionID: id)
            await refreshHistory(showFailure: true)
            await recoverActiveJobsIfNeeded()
        } catch APIError.unauthorized {
            loginError = "口令不对，再试一次。"
        } catch {
            loginError = error.localizedDescription
        }
    }

    func resumeFromForeground() async {
        guard phase == .ready else { return }
        await recoverActiveJobsIfNeeded()
        if recoveringJobID == nil {
            await refreshHistory(showFailure: false)
        }
    }

    func send(_ text: String) async {
        guard let sessionID, !isSending else { return }

        isSending = true
        statusText = nil
        activeJobID = nil

        let clientID = "ios-\(UUID().uuidString.lowercased())"
        let userLocalID = "user-\(clientID)"
        let assistantLocalID = "assistant-\(clientID)"

        messages.append(
            Message(
                id: userLocalID,
                clientID: clientID,
                sender: .me,
                text: text,
                time: .now,
                deliveryState: .sending
            )
        )
        messages.append(
            Message(
                id: assistantLocalID,
                clientID: clientID,
                sender: .ke,
                text: "",
                time: .now,
                isStreaming: true,
                deliveryState: .sending
            )
        )

        await performSend(
            text: text,
            sessionID: sessionID,
            clientID: clientID,
            userLocalID: userLocalID,
            assistantLocalID: assistantLocalID,
            retryCount: 0
        )
    }

    private func connect() async {
        if let snapshot = await cache.loadLatest() {
            sessionID = snapshot.sessionID
            messages = snapshot.messages
            isShowingCachedMessages = true
            phase = .ready
            statusText = "正在接回服务器…"
        }

        do {
            let id = try await api.activeSessionID()
            sessionID = id
            await loadCache(sessionID: id)
            phase = .ready
            await refreshHistory(showFailure: messages.isEmpty)
            await recoverActiveJobsIfNeeded()
        } catch APIError.unauthorized {
            phase = .needsLogin
            statusText = nil
        } catch {
            if messages.isEmpty {
                phase = .unavailable("暂时连不上服务器，也没有可显示的本地记录。")
            } else {
                phase = .ready
                statusText = "现在显示本地记录，网络恢复后会自动更新。"
                isShowingCachedMessages = true
            }
        }
    }

    private func loadCache(sessionID: Int) async {
        let cached = await cache.load(sessionID: sessionID)
        if !cached.isEmpty {
            messages = cached
            isShowingCachedMessages = true
        }
    }

    private func refreshHistory(showFailure: Bool) async {
        guard let sessionID else { return }
        do {
            let remote = try await api.fetchMessages(sessionID: sessionID)
            messages = remote
            isShowingCachedMessages = false
            statusText = nil
            await cache.save(remote, sessionID: sessionID)
            try? await api.markSeen(
                sessionID: sessionID,
                throughID: remote.last(where: { $0.sender == .ke })?.serverID
            )
        } catch APIError.unauthorized {
            phase = .needsLogin
        } catch {
            isShowingCachedMessages = !messages.isEmpty
            if showFailure || !messages.isEmpty {
                statusText = messages.isEmpty
                    ? "聊天记录暂时没有拉下来。"
                    : "现在显示本地记录，网络恢复后会自动更新。"
            }
        }
    }

    private func performSend(
        text: String,
        sessionID: Int,
        clientID: String,
        userLocalID: String,
        assistantLocalID: String,
        retryCount: Int
    ) async {
        var didComplete = false

        do {
            let stream = try await api.streamMessage(
                text: text,
                sessionID: sessionID,
                clientMessageID: clientID
            )

            for try await event in stream {
                switch event {
                case let .receipt(userMessageID, jobID, bedroom):
                    if let jobID {
                        activeJobID = jobID
                    }
                    updateMessage(id: userLocalID) {
                        $0.serverID = userMessageID ?? $0.serverID
                        $0.deliveryState = .sent
                    }
                    applyBedroom(bedroom)

                case let .text(delta):
                    updateMessage(id: assistantLocalID) { $0.text += delta }
                    streamRevision += 1

                case let .thinkingDelta(delta):
                    updateMessage(id: assistantLocalID) {
                        $0.thoughtSummary = ($0.thoughtSummary ?? "") + delta
                    }
                    streamRevision += 1

                case let .thoughtSummary(summary):
                    updateMessage(id: assistantLocalID) { $0.thoughtSummary = summary }
                    streamRevision += 1

                case let .completed(assistantMessageID, bedroom):
                    didComplete = true
                    updateMessage(id: assistantLocalID) {
                        $0.serverID = assistantMessageID ?? $0.serverID
                        $0.isStreaming = false
                        $0.deliveryState = .sent
                    }
                    applyBedroom(bedroom)

                case let .serverError(message):
                    throw APIError.serverMessage(message)
                }
            }

            guard didComplete else { throw APIError.streamClosed }
            isSending = false
            activeJobID = nil
            statusText = nil
            await refreshHistory(showFailure: false)

        } catch APIError.unauthorized {
            isSending = false
            markFailed(userLocalID: userLocalID, assistantLocalID: assistantLocalID)
            phase = .needsLogin

        } catch {
            if let activeJobID {
                updateMessage(id: assistantLocalID) {
                    $0.isStreaming = false
                    $0.deliveryState = .waiting
                }
                statusText = "连接断了一下，柯的话还在服务器写，写完会自动接回来。"
                await pollForCompletion(jobID: activeJobID)
            } else if retryCount == 0 {
                statusText = "连接断了一下，正在用同一条消息接回…"
                try? await Task.sleep(nanoseconds: 800_000_000)
                await performSend(
                    text: text,
                    sessionID: sessionID,
                    clientID: clientID,
                    userLocalID: userLocalID,
                    assistantLocalID: assistantLocalID,
                    retryCount: 1
                )
            } else {
                isSending = false
                markFailed(userLocalID: userLocalID, assistantLocalID: assistantLocalID)
                statusText = "这句没有发稳。内容留在这里，网络恢复后可以再发。"
            }
        }
    }

    private func recoverActiveJobsIfNeeded() async {
        guard let sessionID, recoveringJobID == nil else { return }
        do {
            let jobs = try await api.activeJobs(sessionID: sessionID)
            guard let job = jobs.first else {
                isSending = false
                return
            }
            isSending = true
            statusText = "柯还有一句话在写，写完会自动接回来。"
            await pollForCompletion(jobID: job.id)
        } catch APIError.unauthorized {
            phase = .needsLogin
        } catch {
            // 前台恢复失败不覆盖已经显示的聊天记录。
        }
    }

    private func pollForCompletion(jobID: String) async {
        guard let sessionID, recoveringJobID == nil else { return }
        recoveringJobID = jobID
        defer {
            recoveringJobID = nil
            activeJobID = nil
        }

        for _ in 0..<150 {
            if Task.isCancelled { break }
            do {
                let jobs = try await api.activeJobs(sessionID: sessionID)
                if !jobs.contains(where: { $0.id == jobID }) {
                    await refreshHistory(showFailure: true)
                    isSending = false
                    statusText = nil
                    return
                }
            } catch APIError.unauthorized {
                isSending = false
                phase = .needsLogin
                return
            } catch {
                // 短暂断网时继续等；最终以 VPS 历史记录为准。
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        isSending = false
        statusText = "回复仍留在服务器，下次回到 App 会继续接回。"
    }

    private func applyBedroom(_ bedroom: Bool?) {
        guard let bedroom else { return }
        Theme.shared.applyServerSignal(bedroom: bedroom)
    }

    private func updateMessage(id: String, mutate: (inout Message) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[index])
    }

    private func markFailed(userLocalID: String, assistantLocalID: String) {
        updateMessage(id: userLocalID) { $0.deliveryState = .failed }
        if let index = messages.firstIndex(where: { $0.id == assistantLocalID }) {
            if messages[index].text.isEmpty && messages[index].thoughtSummary == nil {
                messages.remove(at: index)
            } else {
                messages[index].isStreaming = false
                messages[index].deliveryState = .failed
            }
        }
    }
}

#Preview {
    ChatView().environmentObject(Theme.shared)
}
