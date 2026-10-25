import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Network

@MainActor
final class ChatViewModel: ObservableObject {
    private let sendHaptics = SendReceiptHaptics()
    enum Phase: Equatable {
        case checking
        case needsLogin
        case ready
        case unavailable(String)
    }

    struct ReplyFailure: Equatable, Sendable {
        let jobID: String
        let clientMessageID: String
        let userMessageID: Int?
        let message: String
        let canRetry: Bool
    }

    @Published var phase: Phase = .checking
    @Published var messages: [Message] = []
    @Published var statusText: String?
    @Published var loginError: String?
    @Published var isLoggingIn = false
    @Published var isSending = false
    @Published var isShowingCachedMessages = false
    @Published var isLoadingHistory = false
    @Published var historyLoadFailed = false
    @Published var streamRevision = 0
    @Published var modelOptions: [ChatModelOption] = []
    @Published var modelGroups: [ChatModelGroup] = []
    @Published var modelQuotaCatalog: ChatModelQuotaCatalog?
    @Published var selectedModel: String?
    @Published var isLoadingModels = false
    @Published var isLoadingModelQuotas = false
    @Published var isSelectingModel = false
    @Published var isRefreshingClaude = false
    @Published var claudeRefreshNotice: String?
    @Published var claudeRefreshError: String?
    @Published private(set) var hasNetworkPath = false
    @Published var modelError: String?
    @Published var modelQuotaError: String?
    @Published var searchCorpus: [Message] = []
    @Published var isPreparingSearch = false
    @Published var searchError: String?
    @Published var isClearingWindow = false
    @Published var clearWindowNotice: String?
    @Published var clearWindowError: String?
    private var clearRequestID: String?
    @Published var isDeleting = false
    @Published var deleteError: String?
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var isUploading = false
    @Published var uploadingFileName: String?
    @Published var uploadError: String?
    @Published var canRetryUpload = false
    @Published var replyFailure: ReplyFailure?
    @Published private var visibleSegmentCounts: [String: Int] = [:]

    /// 137：没发出去的那句，要放回输入框的字。ChatView 看到后（输入框空着才放）放进草稿，随即清掉
    struct RestoredDraft: Equatable {
        let id = UUID()
        let messageID: String
        let text: String
    }
    @Published var restoredDraft: RestoredDraft?
    /// 137：没发稳的那几句当时真发出去的附件（按 clientID），重发时原样带上
    private var failedSends: [String: [ChatAttachment]] = [:]
    /// 137：从输入框发的那几句（按 clientID）。只有这些没发稳时才把字放回输入框；
    /// 塔罗、日记替她说的那句不放
    private var composerClientIDs: Set<String> = []

    private let api: APIClient
    private let replyAPI: any ChatReplyTransport
    private let replyCompleted: @MainActor () -> Void
    private var replyTask: Task<Void, Never>?
    private var replyOwner: UUID?
    private var historyRequestID: UUID?
    private var enteredBackground = false
    private var inactiveSince: Date?
    private struct PendingReply {
        let clientID: String
        let userLocalID: String
        let assistantLocalID: String
        let text: String
        let attachments: [ChatAttachment]
        let reduceMotion: Bool
    }
    private var pendingReply: PendingReply?
    private var pendingReceipts: [String: PendingReply] = [:]
    private var receiptTasks: [String: (owner: UUID, task: Task<Void, Never>)] = [:]
    private let cache: ChatCache
    @Published private var sessionID: Int?
    @Published private var externalSessionReady = false
    private var acceptedExternalMessages: Set<UUID> = []
    private var didBootstrap = false
    private var isConnecting = false
    private var activeJobID: String?
    private var recoveringJobID: String?
    private var activeStreamClientID: String?
    private var recoveryProbeID: UUID?
    /// 119：回前台/点推送起的那一轮接回。点一下推送会连着来两三次 resume，
    /// 刚起的这一轮还健康就别打断重来（打断会把正在拉的记录作废，转圈更久）。
    private var recoveryOwner: UUID?
    private var recoveryStartedAt: Date?
    /// 119：服务器已经写完的那几句（按 clientID）。合并记录时本机的半截气泡不再保留，
    /// 不然半截和服务器那条完整的会同时出现（她说的「显示两遍」）。
    private var settledReplyClientIDs: Set<String> = []
    private var segmentRevealTasks: [String: Task<Void, Never>] = [:]
    /// 125：一轮回复（发出去、重接、接回）整轮向系统攥着的后台时间。她发完就切走、锁屏时，
    /// 服务器先等她说完（2.5 秒起，她还在打字最多 20 秒）再写，这段时间流一个字都没有；
    /// 以前 App 这时被挂起，流就断在回执后面（nginx 里只有 116 字节），只能等她点推送回来再一问一拉。
    /// 攥着它（约 30 秒），柯写完时这句已经收好、存进缓存。参数是系统到点要收回时的回调，返回「还回去」。
    typealias ReplyKeepAlive = @MainActor (_ onExpire: @escaping @MainActor () -> Void) -> (@MainActor () -> Void)
    private let replyKeepAlive: ReplyKeepAlive
    private var releaseReplyKeepAlive: (@MainActor () -> Void)?
    /// 125：系统收回过后台时间（App 随后被挂起，流可能已经断了）：回前台要重接
    private var replyKeepAliveExpired = false
    /// 125：轮询两问之间的那一下睡。回前台、点推送时叫醒它马上再问，而不是掐断重来
    private var pollNap: Task<Void, Never>?
    /// 125：轮询上一问发出去的时刻；超过 8 秒还没回算卡住
    private var lastPollAt: Date?
    /// 125 修：流还没给 done 的这一轮（按 owner）最近一次收到东西的时刻——服务器每 5 秒一行 `: keepalive`
    /// 也算。10 秒以上一点动静没有算断了（换网、锁屏时连接悄悄死掉），回前台照旧掐断重接，
    /// 不再干等 EventSource 30 秒超时。收到 done、流结束、被掐断都清掉。
    private var streamWatch: (owner: UUID, lastEventAt: Date)?
    /// 125 修：点推送时流还没给 done，起的那一问（问任务写完没有）；同一轮只问一次
    private var streamProbeOwner: UUID?
    /// 125 修：在后台拉回来的记录先不告诉服务器「看过了」，她回到前台再说
    private var deferredSeen: (sessionID: Int, throughID: Int?)?
    /// 125：她从后台回来、或点了推送后的几秒：这时落下来的是她不在时写完的那句（横幅里已经读过），
    /// 整条一次放上，不再一个个冒。过了这几秒才写完的，她是看着落下来的，照常一个个冒。
    private var landWholeUntil: Date?
    private var failedUpload: AttachmentUploadPayload?
    private var lastModelQuotaLoad: Date?
    private var modelQuotaRequestRevision = 0
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "loveapp.chat.connectivity")
    /// 137：网络回来以后等它稳住一下再接（地铁里网络会来回跳）
    private var networkReturnTask: Task<Void, Never>?

    private struct AttachmentUploadPayload {
        let data: Data
        let fileName: String
        let mimeType: String
    }

#if DEBUG
    @Published private(set) var replyStreamTriggerAvailable = false

    private enum UITestFixture: Equatable {
        case thinkingStatic
        case thinkingStreaming
        case replyStreaming
        case segmentedReply
        case longReply
        case veryLongReply
        case scrollControl
        case thinkingSegmentRace
        case sendStability
        case modelGroups
        case replyFailure
        case tarotCards
        case nightCard
    }

    private var uiTestFixture: UITestFixture?
#endif

    init(line: ChatLine = .main, monitorConnectivity: Bool = true,
         replyTransport: (any ChatReplyTransport)? = nil, cacheFileName: String? = nil,
         replyKeepAlive: ReplyKeepAlive? = nil,
         replyCompleted: @escaping @MainActor () -> Void = { CompanionPermissionCoordinator.shared.conversationDidComplete() }) {
        let client = APIClient(baseURL: line.apiBaseURL)
        api = client
        let backgroundKeepAlive: ReplyKeepAlive = { onExpire in
            let grant = BackgroundGrant(name: "ke-reply", onExpire: onExpire)
            return { grant.end() }
        }
#if DEBUG
        let recoveryPreview = ProcessInfo.processInfo.arguments.contains("-ui-test-foreground-recovery")
        let tarotPreview = ProcessInfo.processInfo.arguments.contains("-ui-test-tarot-handoff")
        replyAPI = replyTransport ?? (tarotPreview ? TarotHandoffPreviewTransport() as any ChatReplyTransport : (recoveryPreview ? ChatRecoveryPreviewTransport() as any ChatReplyTransport : client))
        self.replyCompleted = (recoveryPreview || tarotPreview) ? {} : replyCompleted
        cache = ChatCache(fileName: cacheFileName ?? ((recoveryPreview || tarotPreview) ? "chat-preview-\(UUID()).json" : line.cacheFileName))
        // 125：回前台那个 UI 测试的假服务器模拟「App 被挂起、流冻住」：当作后台时间没攥住，回来照常重接
        self.replyKeepAlive = replyKeepAlive ?? (recoveryPreview ? { onExpire in onExpire(); return {} } : backgroundKeepAlive)
#else
        replyAPI = replyTransport ?? client
        self.replyCompleted = replyCompleted
        cache = ChatCache(fileName: cacheFileName ?? line.cacheFileName)
        self.replyKeepAlive = replyKeepAlive ?? backgroundKeepAlive
#endif
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-test-night-card") {
            // 128：平的气泡 + 「夜里日记」卡（假的夜里数据，不连服务器）
            uiTestFixture = .nightCard
            phase = .ready
            sessionID = 1
            NightStore.installPreview(line)
            let t = Date.now
            messages = [
                Message(id: "qq-1", serverID: 601, sender: .me, text: "今天下班好早，想你了", time: t.addingTimeInterval(-900)),
                Message(id: "qq-2", serverID: 602, sender: .ke, text: "那就过来。\n\n我在。", time: t.addingTimeInterval(-880),
                        segments: ["那就过来。", "我在。"]),
                Message(id: "qq-3", serverID: 603, sender: .me, text: "嗯", time: t.addingTimeInterval(-700)),
                Message(id: "qq-4", serverID: 604, sender: .ke,
                        text: "给你看这个 https://www.xiaohongshu.com/explore/6aba0339000000001802e795?xsec_token=ABem2UZRMkV4EO-7cAEnl88OJQVsmV523bgPl-Xjy83-Y=&xsec_source=pc_feed",
                        time: t.addingTimeInterval(-600)),
                Message(id: "qq-5", serverID: 605, sender: .ke, text: "夜里日记 · 刚才那一回", time: t.addingTimeInterval(-60),
                        attachments: [ChatAttachment(url: "ke-night://41", name: "浴室", kind: "night")]),
            ]
        } else if arguments.contains("-ui-test-tarot-cards") {
            uiTestFixture = .tarotCards
            phase = .ready
            sessionID = 1
            let base = "https://jiagude.love/ke-test1/tarot/cards/"
            messages = [
                Message(id: "ui-test-tarot-text", serverID: 501, sender: .ke,
                        text: "想看看你今晚睡不睡得着。\n抽了三牌阵。月亮逆位，星币骑士逆位，星币王后逆位。", time: .now),
                Message(id: "ui-test-tarot-cards", serverID: 502, sender: .ke, text: "", time: .now,
                        attachments: [
                            ChatAttachment(url: base + "major18.webp", name: "月亮·逆位", kind: "image"),
                            ChatAttachment(url: base + "pentacles12.webp", name: "星币骑士·逆位", kind: "image"),
                            ChatAttachment(url: base + "pentacles13.webp", name: "星币王后·逆位", kind: "image"),
                        ]),
            ]
        } else if arguments.contains("-ui-test-reply-failure") {
            uiTestFixture = .replyFailure
            phase = .ready
            sessionID = 1
            messages = [
                Message(
                    id: "ui-test-failed-user",
                    serverID: 42,
                    clientID: "ios-ui-test-failed",
                    sender: .me,
                    text: "爸比？",
                    time: .now
                )
            ]
            replyFailure = ReplyFailure(
                jobID: "ui-test-failed-job",
                clientMessageID: "ios-ui-test-failed",
                userMessageID: 42,
                message: "线路还是没有接稳，柯没有生成完整回复。",
                canRetry: true
            )
        } else if arguments.contains("-ui-test-model-groups") {
            uiTestFixture = .modelGroups
            phase = .ready
            sessionID = 1
            selectedModel = "codex-subscription:gpt-5.5"
            modelGroups = [
                ChatModelGroup(
                    id: "claude_1", label: "Claude 1", available: true,
                    configured: true, message: nil
                ),
                ChatModelGroup(
                    id: "gpt", label: "GPT", available: true,
                    configured: true, message: nil
                ),
                ChatModelGroup(
                    id: "deepseek", label: "DPSK", available: true,
                    configured: true, message: nil
                ),
            ]
            modelOptions = [
                ChatModelOption(
                    id: "claude-subscription-opus-5-5", provider: "claude_subscription",
                    label: "Opus 5.5", description: "Claude Max 模型",
                    group: "claude_subscription", family: "claude_1", available: true
                ),
                ChatModelOption(
                    id: "claude-subscription-sonnet-4-6", provider: "claude_subscription",
                    label: "Sonnet 4.6", description: "Claude Max 备用模型",
                    group: "claude_subscription_backup", family: "claude_1", available: true
                ),
                ChatModelOption(
                    id: "codex-subscription:gpt-5.5", provider: "codex_subscription",
                    label: "GPT-5.5", description: "ChatGPT 的 Codex 订阅额度",
                    group: "codex_subscription", family: "gpt", available: true
                ),
                ChatModelOption(
                    id: "deepseek-v4-pro", provider: "deepseek",
                    label: "V4 Pro", description: "DeepSeek 备用线路，不显示 Thinking",
                    group: "deepseek", family: "deepseek", available: true
                ),
            ]
            modelQuotaCatalog = ChatModelQuotaCatalog(
                updatedAt: Date.now.timeIntervalSince1970,
                selectedGroup: "gpt",
                currentRouteGroup: "gpt",
                groups: [
                    ChatModelQuotaGroup(
                        id: "gpt", label: "GPT", configured: true,
                        available: true, status: "available", usedPercent: 4,
                        remainingPercent: 96, resetAt: Date.now.addingTimeInterval(86_400).timeIntervalSince1970,
                        stale: false, source: "provider",
                        windows: [
                            ChatModelQuotaWindow(
                                kind: "primary", usedPercent: 4, remainingPercent: 96,
                                windowMinutes: 10_080,
                                resetAt: Date.now.addingTimeInterval(86_400).timeIntervalSince1970
                            )
                        ]
                    ),
                ]
            )
            messages = [
                Message(
                    id: "ui-test-model-groups-message",
                    sender: .ke,
                    text: "聊天记录保持原位。",
                    time: .now
                )
            ]
        } else if arguments.contains("-ui-test-thinking-static") {
            uiTestFixture = .thinkingStatic
            phase = .ready
            messages = [
                Message(
                    id: "ui-test-user",
                    sender: .me,
                    text: "你刚刚在想什么？",
                    time: .now
                ),
                Message(
                    id: "ui-test-assistant",
                    sender: .ke,
                    text: "我先把你的话接稳，再慢慢说给你听。",
                    time: .now,
                    thoughtSummary: "心口软了一下。她是在确认我还在不在，我不想让她落空。",
                    thoughtSummaryRaw: "Hold her words first, then answer gently."
                )
            ]
        } else if arguments.contains("-ui-test-thinking-streaming") {
            uiTestFixture = .thinkingStreaming
            phase = .ready
            isSending = true
            messages = [
                Message(
                    id: "ui-test-streaming-user",
                    sender: .me,
                    text: "慢慢想，我在这里。",
                    time: .now
                ),
                Message(
                    id: "ui-test-streaming-assistant",
                    sender: .ke,
                    text: "",
                    time: .now,
                    thoughtSummary: "她还在这里等我。",
                    isStreaming: true,
                    deliveryState: .sending
                )
            ]
        } else if arguments.contains("-ui-test-reply-streaming") {
            uiTestFixture = .replyStreaming
            replyStreamTriggerAvailable = true
            phase = .ready
            isSending = true
            messages = [
                Message(
                    id: "ui-test-reply-streaming-user",
                    sender: .me,
                    text: "一句一句说给我听。",
                    time: .now
                ),
                // 121：写的过程中不再露半截，正文等写完整条放上去
                Message(
                    id: "ui-test-reply-streaming-assistant",
                    sender: .ke,
                    text: "",
                    time: .now,
                    isStreaming: true,
                    deliveryState: .sending
                )
            ]
        } else if arguments.contains("-ui-test-segmented-reply") {
            uiTestFixture = .segmentedReply
            phase = .ready
            let message = Message(
                id: "ui-test-segmented-assistant",
                serverID: 9001,
                sender: .ke,
                text: "第一句先接住你。\n\n第二句慢一点出来。\n\n   \n第三句最后跟上。",
                time: .now
            )
            messages = [message]
            visibleSegmentCounts[message.bubbleRevealKey] = 1
        } else if arguments.contains("-ui-test-long-reply") {
            uiTestFixture = .longReply
            phase = .ready
            messages = [
                Message(
                    id: "ui-test-long-assistant",
                    sender: .ke,
                    text: "这声倒是睡饱了的音儿。哭过、睡过、雨还在落，爸爸也在听雨。",
                    time: .now
                )
            ]
        } else if arguments.contains("-ui-test-very-long-reply") {
            uiTestFixture = .veryLongReply
            phase = .ready
            messages = [
                Message(
                    id: "ui-test-very-long-assistant",
                    sender: .ke,
                    text: "",
                    time: .now.addingTimeInterval(-120),
                    isStreaming: true,
                    deliveryState: .sending
                ),
                Message(
                    id: "ui-test-after-long-user",
                    sender: .me,
                    text: "这是长文后面的消息。",
                    time: .now.addingTimeInterval(-60)
                ),
                Message(
                    id: "ui-test-after-long-assistant",
                    sender: .ke,
                    text: "这是最底下一条消息。",
                    time: .now,
                    thoughtSummary: "长文再长，也不能把她后面的话压住。"
                )
            ]
        } else if arguments.contains("-ui-test-scroll-control")
                    || arguments.contains("-ui-test-send-stability")
                    || arguments.contains("-ui-test-thinking-segment-race") {
            if arguments.contains("-ui-test-thinking-segment-race") {
                uiTestFixture = .thinkingSegmentRace
            } else if arguments.contains("-ui-test-send-stability") {
                uiTestFixture = .sendStability
                sessionID = 1
            } else {
                uiTestFixture = .scrollControl
                sessionID = 1
            }
            phase = .ready
            var fixtureMessages: [Message] = []
            for index in 0..<7 {
                fixtureMessages.append(Message(
                    id: "ui-test-history-user-\(index)",
                    serverID: 9000 + index,
                    sender: .me,
                    text: "前面的消息 \(index + 1)",
                    time: .now.addingTimeInterval(Double(index - 14) * 60)
                ))
                fixtureMessages.append(Message(
                    id: "ui-test-history-ke-\(index)",
                    sender: .ke,
                    text: "前面的回复 \(index + 1)，用来把聊天列表撑过一屏。",
                    time: .now.addingTimeInterval(Double(index - 13) * 60)
                ))
            }
            let latest = Message(
                id: "ui-test-scroll-latest",
                serverID: 9101,
                sender: .ke,
                text: arguments.contains("-ui-test-thinking-segment-race")
                    ? "第一条气泡已经到了。\n\n第二条气泡随后出现。\n\n第三条气泡最后出现。"
                    : "这是最新一条回复。",
                time: .now,
                thoughtSummary: "她点开时不该被屏幕拽着跑。看着那一跳，我自己都烦。"
            )
            fixtureMessages.append(latest)
            messages = fixtureMessages
            if uiTestFixture == .thinkingSegmentRace {
                visibleSegmentCounts[latest.bubbleRevealKey] = 1
            }
        }
#endif
#if DEBUG
        if uiTestFixture != nil {
            externalSessionReady = sessionID != nil
            hasNetworkPath = true
            return
        }
#endif
        if monitorConnectivity {
            networkMonitor.pathUpdateHandler = { [weak self] path in
                let available = path.status == .satisfied
                Task { @MainActor [weak self] in
                    self?.setNetworkPathAvailable(available)
                }
            }
            networkMonitor.start(queue: networkQueue)
        }
    }

    deinit {
        networkMonitor.cancel(); replyTask?.cancel()
        for entry in receiptTasks.values { entry.task.cancel() }
    }

    func setNetworkPathAvailable(_ available: Bool) {
        let regained = available && !hasNetworkPath
        hasNetworkPath = available
        guard available else {
            networkReturnTask?.cancel()
            networkReturnTask = nil
            return
        }
        // 137：没网时打开的（顶上写着「网络恢复后会自动更新」）：网络回来稳住 1 秒，自己接回服务器，
        // 她一直停在这页也会更新，不用切出去再回来
        guard regained, needsReconnectAfterOffline else { return }
        networkReturnTask?.cancel()
        networkReturnTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self, self.hasNetworkPath else { return }
            self.networkReturnTask = nil
            await self.reconnectAfterOffline()
        }
    }

    /// 137：还没接上服务器（没网时打开，只显示本地记录），或者打开时一句也没拉到
    private var needsReconnectAfterOffline: Bool {
        guard didBootstrap, !isConnecting else { return false }
        switch phase {
        case .ready: return !externalSessionReady || isShowingCachedMessages
        case .unavailable: return true
        default: return false
        }
    }

    /// 137：网络回来、或者回前台时还没接上服务器：只接会话、拉记录、接回进行中的那句。
    /// 不像 connect() 那样重读缓存——那会把本机正在发的、没发稳的气泡盖掉。
    private func reconnectAfterOffline() async {
        switch phase {
        case .unavailable:
            // 本来就没有记录可显示，照「再试一次」从头接
            await retryBootstrap()
            return
        case .ready:
            break
        default:
            return
        }
        guard !isConnecting else { return }
        if externalSessionReady {
            // 会话早接上了，只是记录没拉下来：照回前台那样拉一次
            await resumeFromForeground()
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let active = try await replyAPI.activeSession()
            let sameSession = active.id == sessionID
            prepareForSession(active.id)
            selectedModel = active.model
            CompanionPermissionCoordinator.shared.sessionDidBecomeReady()
            if !sameSession { await loadCache(sessionID: active.id) }
            await refreshHistory(showFailure: messages.isEmpty)
            await recoverActiveJobsIfNeeded()
            externalSessionReady = true
        } catch APIError.unauthorized {
            phase = .needsLogin
            statusText = nil
        } catch {
            // 还是连不上：照旧显示本地记录，等下一次网络回来或者回前台
        }
    }

    func bootstrap() async {
#if DEBUG
        if let uiTestFixture {
            if uiTestFixture == .thinkingStreaming {
                await runUITestThinkingStream()
            } else if uiTestFixture == .segmentedReply {
                stageSegments(for: messages[0], reduceMotion: false)
            } else if uiTestFixture == .veryLongReply {
                await runUITestVeryLongGrowth()
            }
            return
        }
#endif
        guard !didBootstrap else { return }
        didBootstrap = true
        await connect()
    }

#if DEBUG
    private func runUITestThinkingStream() async {
        let messageID = "ui-test-streaming-assistant"
        let chunks = [
            "她这句等得很轻，",
            "越轻越像是在怕我没听见。",
            "心里那一下是真的软了。"
        ]

        for chunk in chunks {
            try? await Task.sleep(nanoseconds: 420_000_000)
            updateMessage(id: messageID) {
                $0.thoughtSummary = ($0.thoughtSummary ?? "") + chunk
            }
            streamRevision += 1
        }

        try? await Task.sleep(nanoseconds: 420_000_000)
        updateMessage(id: messageID) {
            $0.text = "想好了，我会一直用中文把心里的话说给你听。"
            $0.isStreaming = false
            $0.deliveryState = .sent
        }
        isSending = false
        streamRevision += 1
    }

    private func runUITestReplyStream() async {
        let messageID = "ui-test-reply-streaming-assistant"
        let chunks = [
            "第一句先来到屏幕上，",
            "第二句接着流进同一个气泡，",
            "最后一句再慢慢说完。"
        ]

        // 121：和真的回复流一样，只收不显示，写完整条放上去
        var replyText = ""
        for chunk in chunks {
            try? await Task.sleep(nanoseconds: 420_000_000)
            replyText += chunk
        }

        updateMessage(id: messageID) {
            $0.text = replyText
            $0.isStreaming = false
            $0.deliveryState = .sent
        }
        isSending = false
        streamRevision += 1
    }

    func startReplyStreamForUITest() async {
        guard uiTestFixture == .replyStreaming,
              replyStreamTriggerAvailable else { return }
        replyStreamTriggerAvailable = false
        await runUITestReplyStream()
    }

    func didOpenThinkingForUITest(messageID: String) {
        guard uiTestFixture == .thinkingSegmentRace,
              messageID == "ui-test-scroll-latest",
              let message = messages.first(where: { $0.id == messageID }),
              segmentRevealTasks[message.bubbleRevealKey] == nil else { return }
        stageSegments(for: message, reduceMotion: false)
    }

    private func runUITestVeryLongGrowth() async {
        try? await Task.sleep(nanoseconds: 350_000_000)
        let paragraph = "爸爸把这段话一行一行说清楚，不省略，也不让后面的消息压上来。你可以慢慢看，手指往下滑的时候，每一行都应该稳稳待在自己的气泡里。"
        let continuous = String(
            repeating: "这是一段没有空行的连续长消息，也必须自然换行并撑开自己的气泡。",
            count: 48
        )
        let longText = Array(repeating: paragraph, count: 18)
            .joined(separator: "\n\n")
            + "\n\n\(continuous)"
            + "\n\n这是长文最后一行，下面的消息不能盖住它。"
        // 121：写完整条放上去（长文整段一个气泡）
        updateMessage(id: "ui-test-very-long-assistant") {
            $0.text = longText
            $0.isStreaming = false
            $0.deliveryState = .sent
        }
        streamRevision += 1
    }

    private func runUITestSendStream(messageID: String) async {
        let chunks = ["爸爸收到了。", "这次屏幕不会再乱跳。"]
        // 121：只收不显示，写完整条放上去
        var replyText = ""
        for chunk in chunks {
            try? await Task.sleep(nanoseconds: 360_000_000)
            replyText += chunk
        }
        updateMessage(id: messageID) {
            $0.text = replyText
            $0.isStreaming = false
            $0.deliveryState = .sent
        }
        isSending = false
        streamRevision += 1
    }
#endif

    func retryBootstrap() async {
        phase = .checking
        await connect()
    }

    func login(passcode: String) async {
        isLoggingIn = true
        externalSessionReady = false
        loginError = nil
        defer { isLoggingIn = false }

        do {
            try await api.login(passcode: passcode)
            let active = try await replyAPI.activeSession()
            prepareForSession(active.id)
            selectedModel = active.model
            phase = .ready
            CompanionPermissionCoordinator.shared.sessionDidBecomeReady()
            await loadCache(sessionID: active.id)
            await refreshHistory(showFailure: true)
            await recoverActiveJobsIfNeeded()
            externalSessionReady = true
        } catch APIError.unauthorized {
            loginError = "口令不对，再试一次。"
        } catch {
            loginError = error.localizedDescription
        }
    }

    func becameInactive(at date: Date = .now) { inactiveSince = inactiveSince ?? date }
    func enteredBackgroundScene() { enteredBackground = true }

    /// userInitiated：她自己点的「重试」——不管这一轮看着多健康，都掐断重来。
    func resumeFromForeground(forceReconnect: Bool = false, userInitiated: Bool = false, at date: Date = .now) async {
#if DEBUG
        if uiTestFixture != nil { return }
#endif
        let wasSuspended = enteredBackground || inactiveSince.map { date.timeIntervalSince($0) >= 2 } == true
        // 125：从后台回来、点推送：接下来几秒里落下来的那句是她不在时写完的，整条放上
        if enteredBackground || forceReconnect { landWholeUntil = date.addingTimeInterval(5) }
        enteredBackground = false
        inactiveSince = nil
        flushDeferredSeen()
        guard phase == .ready else { return }
        // 119：点推送时 scenePhase、openRequest、.task 会各叫一次。头一次已经起了接回，
        // 后面这几次只要那一轮还新鲜（没卡住）就不再打断重来。
        if !wasSuspended, replyTask != nil, replyOwner != nil, replyOwner == recoveryOwner,
           let started = recoveryStartedAt, date.timeIntervalSince(started) < 8 {
            return
        }
        if wasSuspended || forceReconnect {
            // 125：这一轮回复一直攥着后台时间、系统没收回去——App 没被挂起过，流和轮询都还连着。
            // 掐断重来只会把快到手的那句作废、从头再问一遍（她说的「点进去消息还要等」）；
            // 正在轮询就叫醒它马上再问一次。
            if !userInitiated, replyIsLive(at: date) {
                pollNap?.cancel()
                // 点推送 = 服务器那边已经写完了；流健康的话 done 和推送同一刻发出，早该到了。
                // 流还没给 done：不干等，问一下任务，写完了就掐断这条流、按任务接回。
                if forceReconnect, let owner = replyOwner, streamWatch?.owner == owner {
                    probeStreamOnNotificationTap(owner: owner)
                }
                return
            }
#if DEBUG
            ChatRecoveryUITestTiming.shared.begin()
#endif
            // Invalidate ownership BEFORE cancellation can deliver an error or run a defer.
            abandonReplyConnection()
        }
        guard replyTask == nil, activeStreamClientID == nil else { return }
        // 137：没网时打开的、到现在还没接上服务器：先接上会话（拉记录、接回都在里面）
        if !externalSessionReady, !isConnecting {
            await reconnectAfterOffline()
            return
        }
        await recoverActiveJobsIfNeeded()
    }

    func retryHistory() async {
        await resumeFromForeground(forceReconnect: true, userInitiated: true)
    }

    /// 125：这一轮回复还活着——攥着的后台时间没被系统收回（没被挂起过）。
    /// 正在轮询、上一问 8 秒还没回的不算：卡住了，照旧掐断重来。
    private func replyIsLive(at date: Date) -> Bool {
        guard replyTask != nil, replyOwner != nil,
              releaseReplyKeepAlive != nil, !replyKeepAliveExpired else { return false }
        if recoveringJobID != nil, let lastPollAt, date.timeIntervalSince(lastPollAt) >= 8 { return false }
        // 125 修：还在等流的 done，10 秒以上一点动静（连 keepalive 都）没有：连接已经悄悄断了
        if let streamWatch, streamWatch.owner == replyOwner,
           date.timeIntervalSince(streamWatch.lastEventAt) >= 10 { return false }
        return true
    }

    /// 125 修：点推送时流还没给 done。问一下任务：已经写完（或出错、要重试）而流还没送到，
    /// 就是流卡住了——掐断它、按任务接回（拉记录 1～2 秒），不等 EventSource 30 秒超时。
    /// 还在写就留着流（推送可能是别的消息的）。没有回执、问不到的，照 125 以前掐断重来。
    private func probeStreamOnNotificationTap(owner: UUID) {
        guard streamProbeOwner != owner, let sessionID else { return }
        streamProbeOwner = owner
        Task { [self] in
            defer { if streamProbeOwner == owner { streamProbeOwner = nil } }
            @MainActor func streamStillPending() -> Bool {
                replyOwner == owner && streamWatch?.owner == owner && self.sessionID == sessionID
            }
            var stalled = true
            if let jobID = activeJobID {
                do {
                    let job = try await replyAPI.chatJob(id: jobID, sessionID: sessionID)
                    stalled = ["done", "merged", "error", "waiting_retry"].contains(job.status)
                } catch {
                    stalled = true
                }
            }
            guard stalled, streamStillPending() else { return }
            abandonReplyConnection()
            guard replyTask == nil, activeStreamClientID == nil else { return }
            await recoverActiveJobsIfNeeded()
        }
    }

    /// 125 修：流这一轮收到了东西（包括 keepalive）
    private func noteStreamActivity(_ owner: UUID) {
        guard replyOwner == owner else { return }
        streamWatch = (owner, .now)
    }

    private func endStreamWatch(_ owner: UUID) {
        if streamWatch?.owner == owner { streamWatch = nil }
    }

    private func flushDeferredSeen() {
        guard let deferred = deferredSeen else { return }
        deferredSeen = nil
        guard deferred.sessionID == sessionID else { return }
        Task { try? await replyAPI.markSeen(sessionID: deferred.sessionID, throughID: deferred.throughID) }
    }

    /// 125：跑一轮回复（发出去、重接、接回），整轮攥着后台时间；跑完、后面也没接着跑的才还回去。
    /// 被新的一轮顶掉时（replyTask 已经换成新的），后台时间留给新的那一轮接着用。
    private func runReplyTask(_ task: Task<Void, Never>) async {
        replyTask = task
        if releaseReplyKeepAlive == nil {
            replyKeepAliveExpired = false
            let release = replyKeepAlive { [weak self] in
                guard let self else { return }
                self.replyKeepAliveExpired = true
                // 125 修：收回时也照样还一次（还过的再还不算数），不靠 BackgroundGrant 自己那一下
                let release = self.releaseReplyKeepAlive
                self.releaseReplyKeepAlive = nil
                release?()
            }
            // 系统当场没给（expired 已经是 true）也照样记着，跑完一并还
            releaseReplyKeepAlive = release
        }
        await task.value
        if replyTask == nil {
            let release = releaseReplyKeepAlive
            releaseReplyKeepAlive = nil
            release?()
        }
    }

    private func ownsReply(_ owner: UUID) -> Bool {
        replyOwner == owner && !Task.isCancelled
    }

    private func abandonReplyConnection() {
        replyOwner = nil
        let previous = replyTask
        replyTask = nil
        activeStreamClientID = nil
        recoveringJobID = nil
        recoveryProbeID = nil
        historyRequestID = nil
        streamWatch = nil
        previous?.cancel()
        let receipts = receiptTasks.values.map(\.task)
        receiptTasks.removeAll()
        for task in receipts { task.cancel() }
        // Keep the known job/client ID and local draft until authoritative history arrives.
    }

    private func finishReplyTask(_ owner: UUID) {
        guard replyOwner == owner else { return }
        replyTask = nil
        activeStreamClientID = nil
        // Keep owner identity so a history response begun by this owner can still be checked.
        if !isSending && activeJobID == nil { pendingReply = nil }
    }

    func prepareExternalSend() async {
        guard !externalSessionReady, phase != .needsLogin else { return }
        // A cached chat may have opened while offline, even if tarot now has a connection.
        // 137：已经显示着本地记录的不走 connect()（它会重读缓存，盖掉本机没发稳的气泡）
        if phase == .ready {
            await reconnectAfterOffline()
        } else {
            await connect()
        }
    }

    var canAcceptExternalMessage: Bool {
        phase == .ready && externalSessionReady && sessionID != nil && !isRefreshingClaude && !isClearingWindow
    }

    /// Reserve once before any suspension. A repeated view task cannot send twice.
    /// The root retains unaccepted requests while login/session preparation is pending.
    /// shownAttachments：只画在她这条气泡上、不随消息发出去的附件（136：塔罗「交给柯」时那几张牌，
    /// 服务器照 [塔罗#id] 自己挂同样的几张，拉回来时地址和名字都一样，气泡不跳）
    func sendExternalMessage(id: UUID, text: String, shownAttachments: [ChatAttachment] = [], reduceMotion: Bool = false) async -> Bool {
        if acceptedExternalMessages.contains(id) { return true }
        guard canAcceptExternalMessage, !text.isEmpty else { return false }
        acceptedExternalMessages.insert(id)
        await send(text, reduceMotion: reduceMotion, includePendingAttachments: false, shownAttachments: shownAttachments)
        return true
    }

    func send(_ text: String, reduceMotion: Bool = false, includePendingAttachments: Bool = true,
              shownAttachments: [ChatAttachment] = []) async {
        guard let sessionID, !isRefreshingClaude, !isClearingWindow else { return }
        let attachments = includePendingAttachments ? pendingAttachments : []
        guard !text.isEmpty || !attachments.isEmpty else { return }
        let clientID = "ios-\(UUID().uuidString.lowercased())"
        if includePendingAttachments {
            pendingAttachments = []
            composerClientIDs.insert(clientID)
        }
        if isSending {
            await sendWhileReplying(text, sessionID: sessionID, clientID: clientID, userLocalID: "user-\(clientID)",
                                    attachments: attachments, shownAttachments: shownAttachments)
            return
        }
        await startReply(text: text, sessionID: sessionID, clientID: clientID, userLocalID: "user-\(clientID)",
                         attachments: attachments, shownAttachments: shownAttachments, reduceMotion: reduceMotion)
    }

    /// 137：她那句「没有发稳」，长按点了「重发」（或者放回输入框的那句原样又发了一次）：
    /// 原样再发一遍，沿用原来的 clientID——服务器按它去重，其实已经收到的不会记两遍。
    /// 气泡挪到最底下，和刚发的一样。
    func resend(messageID: String, reduceMotion: Bool = false) async {
        guard let sessionID, !isRefreshingClaude, !isClearingWindow,
              let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].canResend, let clientID = messages[index].clientID else { return }
        let failed = messages[index]
        let attachments = resendAttachments(for: failed)
        let sentURLs = Set(attachments.map(\.url))
        // 失败时放回输入框的附件跟着这句一起走，不再留在输入框里（不然下一句又带一遍）
        pendingAttachments.removeAll { sentURLs.contains($0.url) }
        let shown = (failed.attachments ?? []).filter { !sentURLs.contains($0.url) }
        failedSends[clientID] = nil
        pendingReceipts[clientID] = nil
        messages.remove(at: index)
        messages.removeAll { $0.id == "assistant-\(clientID)" && $0.serverID == nil }
        // 换个本机 id：在列表里算新插到最底下的一行，不用整个重排
        let userLocalID = "user-\(clientID)-\(UUID().uuidString.prefix(6).lowercased())"
        if isSending {
            await sendWhileReplying(failed.text, sessionID: sessionID, clientID: clientID, userLocalID: userLocalID,
                                    attachments: attachments, shownAttachments: shown)
            return
        }
        await startReply(text: failed.text, sessionID: sessionID, clientID: clientID, userLocalID: userLocalID,
                         attachments: attachments, shownAttachments: shown, reduceMotion: reduceMotion)
    }

    /// 137：输入框里是放回来的那句、一个字没改、附件也一样：按发送就当重发那一句，不另起一条
    func isUnchangedResend(of messageID: String, text: String) -> Bool {
        guard let failed = messages.first(where: { $0.id == messageID }), failed.canResend,
              failed.text == text else { return false }
        return Set(pendingAttachments.map(\.url)) == Set(resendAttachments(for: failed).map(\.url))
    }

    /// 137：没发出去的那句不要了：只从这台手机上拿掉（服务器要是其实收到了，拉记录时那条照常出现）
    func discardUnsent(messageID: String) async {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].canResend else { return }
        let clientID = messages[index].clientID
        messages.remove(at: index)
        if let clientID {
            failedSends[clientID] = nil
            pendingReceipts[clientID] = nil
            messages.removeAll { $0.sender == .ke && $0.clientID == clientID && $0.serverID == nil }
        }
        if let sessionID { await cache.save(Self.cacheable(messages), sessionID: sessionID) }
    }

    /// 137：重发时带的附件：这次运行里记着当时真发出去的那几个；重开 App 以后只剩气泡上画的，
    /// 塔罗那几张牌是服务器照 [塔罗#id] 自己挂的，不算她发的附件
    private func resendAttachments(for message: Message) -> [ChatAttachment] {
        guard let clientID = message.clientID else { return [] }
        if let sent = failedSends[clientID] { return sent }
        if let pending = pendingReceipts[clientID] { return pending.attachments }
        return (message.attachments ?? []).filter { !$0.url.contains("/tarot/cards/") }
    }

    /// 发一句、等柯回（新发的和重发的都走这里）
    private func startReply(text: String, sessionID: Int, clientID: String, userLocalID: String,
                            attachments: [ChatAttachment], shownAttachments: [ChatAttachment],
                            reduceMotion: Bool) async {
        abandonReplyConnection()
        isSending = true
        statusText = nil
        replyFailure = nil
        activeJobID = nil
        landWholeUntil = nil
        // Invalidate any foreground recovery probe that is currently awaiting the network.
        recoveryProbeID = nil

        sendHaptics.prepare()
        let assistantLocalID = "assistant-\(clientID)"
        activeStreamClientID = clientID
        let owner = UUID()
        replyOwner = owner
        pendingReply = PendingReply(clientID: clientID, userLocalID: userLocalID,
                                    assistantLocalID: assistantLocalID, text: text,
                                    attachments: attachments, reduceMotion: reduceMotion)

        messages.append(
            Message(
                id: userLocalID,
                clientID: clientID,
                sender: .me,
                text: text,
                time: .now,
                attachments: attachments + shownAttachments,
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

#if DEBUG
        if uiTestFixture == .sendStability {
            await runUITestSendStream(messageID: assistantLocalID)
            finishReplyTask(owner)
            return
        }
#endif

        let task = Task { [self] in
            await performSend(text: text, sessionID: sessionID, clientID: clientID,
                              userLocalID: userLocalID, assistantLocalID: assistantLocalID,
                              attachments: attachments, reduceMotion: reduceMotion,
                              retryCount: 0, owner: owner)
            guard ownsReply(owner) else { return }
            activeStreamClientID = nil
            await recoverPendingReceipts(owner: owner)
            guard ownsReply(owner) else { return }
            await drainQueuedFollowUps(owner: owner)
            finishReplyTask(owner)
        }
        await runReplyTask(task)
    }

    /// 柯还在回上一句时她接着发的那几条：已经送到服务器排队，等这一句回完再接着回。
    private var queuedFollowUps: [(clientID: String, jobID: String)] = []

    /// 她在柯回话途中接着发：消息立刻送到服务器、立刻显示，不再锁发送键。
    /// 服务器把排在前面的几条并进最后一条（status=merged），柯看完一起回。
    private func sendWhileReplying(_ text: String, sessionID: Int, clientID: String, userLocalID: String,
                                   attachments: [ChatAttachment], shownAttachments: [ChatAttachment] = []) async {
        guard !text.isEmpty || !attachments.isEmpty else { return }
        messages.append(
            Message(
                id: userLocalID,
                clientID: clientID,
                sender: .me,
                text: text,
                time: .now,
                attachments: attachments + shownAttachments,
                deliveryState: .sending
            )
        )
        let pending = PendingReply(clientID: clientID, userLocalID: userLocalID,
                                   assistantLocalID: "assistant-\(clientID)", text: text,
                                   attachments: attachments, reduceMotion: false)
        pendingReceipts[clientID] = pending
        await obtainReceipt(pending, sessionID: sessionID)
        if !isSending { await recoverActiveJobsIfNeeded() }
    }

    private func obtainReceipt(_ pending: PendingReply, sessionID: Int) async {
        if let existing = receiptTasks[pending.clientID] { await existing.task.value; return }
        let token = UUID()
        let task = Task { [self] in
            @MainActor func isCurrent() -> Bool {
                receiptTasks[pending.clientID]?.owner == token && self.sessionID == sessionID && !Task.isCancelled
            }
            defer { if receiptTasks[pending.clientID]?.owner == token { receiptTasks[pending.clientID] = nil } }
            do {
                let stream = try await replyAPI.streamMessage(text: pending.text, sessionID: sessionID,
                    clientMessageID: pending.clientID, model: selectedModel, attachments: pending.attachments)
                guard isCurrent() else { return }
                for try await event in stream {
                    guard isCurrent() else { return }
                    if case let .receipt(userMessageID, jobID, _) = event {
                        updateMessage(id: pending.userLocalID) {
                            $0.serverID = userMessageID ?? $0.serverID; $0.deliveryState = .sent
                        }
                        if let jobID, !queuedFollowUps.contains(where: { $0.jobID == jobID }) {
                            queuedFollowUps.append((pending.clientID, jobID))
                        }
                        pendingReceipts[pending.clientID] = nil
                        return
                    }
                }
                guard isCurrent() else { return }
                throw APIError.streamClosed
            } catch {
                guard isCurrent() else { return }
                updateMessage(id: pending.userLocalID) { $0.deliveryState = .failed }
                // Keep the original key/payload so foreground recovery can retry safely.
            }
        }
        receiptTasks[pending.clientID] = (token, task)
        await task.value
    }

    private func recoverPendingReceipts(owner: UUID) async {
        guard let sessionID else { return }
        // Preserve send order when multiple receipts were suspended.
        let pending = pendingReceipts.values.sorted { a, b in
            (messages.firstIndex { $0.id == a.userLocalID } ?? 0)
                < (messages.firstIndex { $0.id == b.userLocalID } ?? 0)
        }
        for request in pending {
            guard ownsReply(owner) else { return }
            await obtainReceipt(request, sessionID: sessionID)
        }
    }

    /// 上一句回完以后，跟着回她途中补发的那几条：只盯最后一条，前面的服务器已经并进来了。
    private func drainQueuedFollowUps(owner: UUID) async {
        while ownsReply(owner), let last = queuedFollowUps.last {
            queuedFollowUps.removeAll()
            let assistantLocalID = "assistant-\(last.clientID)"
            isSending = true
            if !messages.contains(where: { $0.clientID == last.clientID && $0.sender == .ke }) {
                messages.append(
                    Message(
                        id: assistantLocalID,
                        clientID: last.clientID,
                        sender: .ke,
                        text: "",
                        time: .now,
                        isStreaming: true,
                        deliveryState: .sending
                    )
                )
            }
            // 137：重发过的那句本机 id 不是「user-clientID」，按 clientID 找她那条
            let userLocalID = messages.first(where: { $0.clientID == last.clientID && $0.sender == .me })?.id
                ?? "user-\(last.clientID)"
            pendingReply = PendingReply(clientID: last.clientID,
                                        userLocalID: userLocalID, assistantLocalID: assistantLocalID,
                                        text: "", attachments: [], reduceMotion: false)
            activeJobID = last.jobID
            await pollForCompletion(
                jobID: last.jobID,
                fallbackClientID: last.clientID,
                fallbackUserMessageID: messages.first(where: {
                    $0.clientID == last.clientID && $0.sender == .me
                })?.serverID,
                assistantLocalID: assistantLocalID, owner: owner
            )
        }
    }

    func addAttachment(data: Data, fileName: String, mimeType: String) async {
        guard !isUploading else {
            reportUploadFailure("上一份附件还在上传，请等它完成。")
            return
        }
        guard pendingAttachments.count < 9 else {
            reportUploadFailure("一次最多发送 9 个附件。")
            return
        }
        guard data.count < 29 * 1024 * 1024 else {
            reportUploadFailure("文件需要小于 29MB。")
            return
        }
        let payload = AttachmentUploadPayload(
            data: data,
            fileName: fileName,
            mimeType: mimeType
        )
        failedUpload = nil
        canRetryUpload = false
        await upload(payload)
    }

    private func upload(_ payload: AttachmentUploadPayload) async {
        isUploading = true
        uploadingFileName = payload.fileName
        uploadError = nil
        defer {
            isUploading = false
            uploadingFileName = nil
        }
        do {
            let uploaded = try await api.uploadAttachment(
                data: payload.data,
                fileName: payload.fileName,
                mimeType: payload.mimeType
            )
            if !pendingAttachments.contains(where: { $0.url == uploaded.url }) {
                pendingAttachments.append(uploaded)
            }
            failedUpload = nil
            canRetryUpload = false
        } catch {
            failedUpload = payload
            canRetryUpload = true
            uploadError = error.localizedDescription
        }
    }

    func retryLastUpload() async {
        guard !isUploading, let failedUpload else { return }
        canRetryUpload = false
        await upload(failedUpload)
    }

    func reportUploadFailure(_ message: String) {
        uploadError = message
        canRetryUpload = failedUpload != nil
    }

    func addPhotoAttachment(data: Data, fileName: String, mimeType: String) async {
        let allowed = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp"]
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()

        // 动图保留原文件；普通照片统一缩边并转成 JPEG。相册和系统照片选择器
        // 经常给出四五千万像素的 HEIC/JPEG，直接上传会长时间占着转圈状态。
        if ext == "gif" {
            await addAttachment(data: data, fileName: fileName, mimeType: mimeType)
            return
        }
        guard let image = UIImage(data: data),
              let jpeg = image.chatUploadJPEGData() else {
            if allowed.contains(ext) {
                await addAttachment(data: data, fileName: fileName, mimeType: mimeType)
                return
            }
            reportUploadFailure("这张照片的格式暂时不能发送。")
            return
        }
        await addAttachment(
            data: jpeg,
            fileName: "照片-\(UUID().uuidString.prefix(8)).jpg",
            mimeType: "image/jpeg"
        )
    }

    func addFile(url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                reportUploadFailure("这个项目不是可以发送的文件。")
                return
            }
            guard (values.fileSize ?? 0) < 29 * 1024 * 1024 else {
                reportUploadFailure("文件需要小于 29MB。")
                return
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let type = UTType(filenameExtension: url.pathExtension)
            await addAttachment(
                data: data,
                fileName: url.lastPathComponent,
                mimeType: type?.preferredMIMEType ?? "application/octet-stream"
            )
        } catch {
            reportUploadFailure("没有读取到这个文件。")
        }
    }

    func removePendingAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
        if pendingAttachments.isEmpty, failedUpload == nil { uploadError = nil }
    }

    func loadModels(force: Bool = false) async {
#if DEBUG
        if uiTestFixture == .modelGroups { return }
#endif
        guard force || modelOptions.isEmpty else { return }
        isLoadingModels = true
        modelError = nil
        defer { isLoadingModels = false }
        do {
            let catalog = try await api.fetchModels()
            modelOptions = catalog.options.isEmpty
                ? catalog.models.map {
                    ChatModelOption(
                        id: $0,
                        provider: nil,
                        label: nil,
                        description: nil,
                        group: nil,
                        family: nil,
                        available: true
                    )
                }
                : catalog.options
            modelGroups = catalog.groups ?? []
            let availableModelIDs = Set(modelOptions.map(\.id))
            if selectedModel == nil || !availableModelIDs.contains(selectedModel ?? "") {
                selectedModel = catalog.default
            }
        } catch {
            modelError = error.localizedDescription
        }
    }

    func loadModelSettings(force: Bool = false) async {
        async let models: Void = loadModels(force: force)
        async let quotas: Void = loadModelQuotas(force: force)
        _ = await (models, quotas)
    }

    func loadModelQuotas(force: Bool = false) async {
#if DEBUG
        if uiTestFixture == .modelGroups { return }
#endif
        guard let sessionID else { return }
        if !force,
           let lastModelQuotaLoad,
           Date().timeIntervalSince(lastModelQuotaLoad) < 30 {
            return
        }
        guard force || !isLoadingModelQuotas else { return }
        modelQuotaRequestRevision += 1
        let requestRevision = modelQuotaRequestRevision
        isLoadingModelQuotas = true
        // 124：刷新时不先清空。上次读到的额度一直留着，新的读到了才换；
        // 没读到也不丢旧的（页面会说「这是上次读到的」），错误也等有了结果再改。
        defer {
            if requestRevision == modelQuotaRequestRevision {
                isLoadingModelQuotas = false
            }
        }
        do {
            let catalog = try await api.fetchModelQuotas(sessionID: sessionID)
            guard requestRevision == modelQuotaRequestRevision else { return }
            modelQuotaCatalog = catalog
            modelQuotaError = nil
            lastModelQuotaLoad = Date()
        } catch {
            // 124：页面关了把这次读取取消掉，不算没读到（不然下次打开先挂着一句「上次的」）
            guard requestRevision == modelQuotaRequestRevision, !Task.isCancelled else { return }
            modelQuotaError = "额度暂时没读到，点刷新再试。"
        }
    }

    func selectModel(_ model: String) async {
        guard !isRefreshingClaude else { return }
        claudeRefreshNotice = nil
        claudeRefreshError = nil
#if DEBUG
        if uiTestFixture == .modelGroups {
            isSelectingModel = true
            defer { isSelectingModel = false }
            try? await Task.sleep(nanoseconds: 250_000_000)
            selectedModel = model
            let groupID = modelOptions.first(where: { $0.id == model }).map {
                ChatModelSection.normalizedGroup($0.family ?? $0.group ?? $0.provider ?? "")
            }
            if let catalog = modelQuotaCatalog {
                modelQuotaCatalog = ChatModelQuotaCatalog(
                    updatedAt: catalog.updatedAt,
                    selectedGroup: groupID,
                    currentRouteGroup: groupID,
                    groups: catalog.groups
                )
            }
            return
        }
#endif
        guard let sessionID, !isSelectingModel, !isClearingWindow else { return }
        isSelectingModel = true
        modelError = nil
        defer { isSelectingModel = false }
        do {
            let active = try await api.selectModel(sessionID: sessionID, model: model)
            selectedModel = active.model ?? model
            // 124：换了模型也先留着各号的额度，重读回来再换，别让那几行字一闪没了
            await loadModelQuotas(force: true)
        } catch {
            modelError = error.localizedDescription
        }
    }

    var canClearWindow: Bool {
        phase == .ready && !isSending && !isDeleting && !isSelectingModel && !isPreparingSearch
            && !isRefreshingClaude && !isClearingWindow && hasNetworkPath
    }

    func clearCurrentWindow() async {
        guard canClearWindow, let oldSessionID = sessionID else { return }
        isClearingWindow = true
        clearWindowError = nil
        clearWindowNotice = nil
        defer { isClearingWindow = false }
        let requestID = clearRequestID ?? UUID().uuidString
        clearRequestID = requestID
        do {
            let newSessionID: Int
#if DEBUG
            if uiTestFixture == .modelGroups {
                newSessionID = oldSessionID + 1
            } else {
                newSessionID = try await api.clearChatWindow(sessionID: oldSessionID, requestID: requestID)
            }
#else
            newSessionID = try await api.clearChatWindow(sessionID: oldSessionID, requestID: requestID)
#endif
            sessionID = newSessionID
            messages = []
            searchCorpus = []
            isShowingCachedMessages = false
            historyLoadFailed = false
            applyBedroom(false)
            activeJobID = nil
            activeStreamClientID = nil
            await cache.save([], sessionID: newSessionID)
            clearRequestID = nil
            clearWindowNotice = "当前聊天已清空，下一条从新的上下文开始。事实记忆保留。"
        } catch {
            clearWindowError = "没有确认清空成功。\(error.localizedDescription)"
        }
    }

    var canRefreshClaude: Bool {
        let isClaude = selectedModel?.hasPrefix("claude-subscription-") == true
            || selectedModel?.hasPrefix("claude2-subscription-") == true
        return phase == .ready && isClaude && !isSending && !isSelectingModel
            && !isRefreshingClaude && !isClearingWindow && !isShowingCachedMessages && hasNetworkPath
    }

    func refreshClaudeSession() async {
        guard canRefreshClaude, let sessionID, let selectedModel else { return }
        isRefreshingClaude = true
        claudeRefreshError = nil
        claudeRefreshNotice = nil
        defer { isRefreshingClaude = false }
#if DEBUG
        if uiTestFixture == .modelGroups {
            claudeRefreshNotice = "下一条消息会用新的 Claude 会话。聊天记录和记忆都保留。"
            return
        }
#endif
        do {
            _ = try await api.refreshClaudeSession(sessionID: sessionID, model: selectedModel)
            claudeRefreshNotice = "下一条消息会用新的 Claude 会话。聊天记录和记忆都保留。"
        } catch {
            claudeRefreshError = "没有确认刷新成功。\(error.localizedDescription)，请稍后重试。"
        }
    }

    func prepareSearchCorpus(force: Bool = false) async {
        guard let sessionID else { return }
        guard force || searchCorpus.isEmpty else { return }
        isPreparingSearch = true
        searchError = nil
        defer { isPreparingSearch = false }

        do {
            var collected = messages.filter { $0.serverID != nil }
            var currentBeforeID = collected.compactMap(\.serverID).min()
            for _ in 0..<4 {
                guard let beforeID = currentBeforeID else { break }
                let page = try await api.fetchMessages(
                    sessionID: sessionID,
                    limit: 100,
                    beforeID: beforeID
                )
                guard !page.isEmpty else { break }
                collected = mergeMessages(collected, with: page)
                guard page.count >= 100 else { break }
                let next = page.compactMap(\.serverID).min()
                guard next != beforeID else { break }
                currentBeforeID = next
            }
            searchCorpus = collected.sorted { ($0.serverID ?? 0) < ($1.serverID ?? 0) }
        } catch {
            searchCorpus = messages
            searchError = "较早的记录暂时没拉下来；仍可搜索当前本地缓存。"
        }
    }

    func searchResults(for query: String) -> [Message] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return Array(searchCorpus
            .filter { $0.text.localizedCaseInsensitiveContains(needle) }
            .suffix(80)
            .reversed())
    }

    var deletionCandidates: [Message] {
        let source = searchCorpus.isEmpty ? messages : searchCorpus
        return source
            .filter { $0.serverID != nil }
            .sorted { ($0.serverID ?? 0) > ($1.serverID ?? 0) }
    }

    func revealSearchResult(_ message: Message) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages = mergeMessages(messages, with: searchCorpus)
    }

    /// Read-only navigation: never changes the active server session or creates a message.
    func revealQuotedMessage(serverID: Int) async throws -> Message {
        if let found = messages.first(where: { $0.serverID == serverID }) { return found }
        guard let sessionID else { throw APIError.invalidResponse }
        let originalSession = sessionID
        let nearby = try await replyAPI.fetchMessages(sessionID: sessionID, limit: 60, beforeID: nil, aroundID: serverID)
        try Task.checkCancellation()
        guard self.sessionID == originalSession,
              let target = nearby.first(where: { $0.serverID == serverID }) else { throw APIError.invalidResponse }
        messages = mergeMessages(messages, with: nearby)
        return target
    }

    func deleteMessages(ids: Set<Int>) async -> Set<Int> {
        guard !ids.isEmpty, !isDeleting else { return [] }
        isDeleting = true
        deleteError = nil
        defer { isDeleting = false }

        var deleted: Set<Int> = []
        for id in ids.sorted() {
            do {
                try await api.deleteMessage(id: id)
                deleted.insert(id)
            } catch {
                deleteError = "有些记录没有删成功，可以再试一次。"
                break
            }
        }
        guard !deleted.isEmpty else { return deleted }
        messages.removeAll { $0.serverID.map(deleted.contains) == true }
        searchCorpus.removeAll { $0.serverID.map(deleted.contains) == true }
        if let sessionID { await cache.save(Self.cacheable(messages), sessionID: sessionID) }
        return deleted
    }

    private func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        externalSessionReady = false
        if let snapshot = await cache.loadLatest() {
            prepareForSession(snapshot.sessionID)
            messages = Self.cacheable(snapshot.messages)
            isShowingCachedMessages = true
            phase = .ready
            statusText = "正在接回服务器…"
        }

        do {
            let active = try await replyAPI.activeSession()
            prepareForSession(active.id)
            selectedModel = active.model
            CompanionPermissionCoordinator.shared.sessionDidBecomeReady()
            await loadCache(sessionID: active.id)
            phase = .ready
            await refreshHistory(showFailure: messages.isEmpty)
            await recoverActiveJobsIfNeeded()
            externalSessionReady = true
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

    /// 119：柯还没落到服务器的本机气泡（没有 serverID）不进缓存。重开 App 后没有对应的
    /// pendingReply 能接回它，留着就会和服务器那条完整的一起显示，还一直像在写。
    private static func cacheable(_ messages: [Message]) -> [Message] {
        messages.filter { $0.sender == .me || $0.serverID != nil }
    }

    private func loadCache(sessionID: Int) async {
        let stored = await cache.load(sessionID: sessionID)
        let cached = Self.cacheable(stored)
        guard self.sessionID == sessionID, !cached.isEmpty else { return }
        // Cache I/O may finish after send() has created local bubbles. Always merge
        // so streaming, waiting and failed local bubbles remain addressable.
        messages = mergeRemoteHistory(cached)
        if !messages.isEmpty {
            isShowingCachedMessages = true
        }
    }

    @discardableResult
    private func refreshHistory(showFailure: Bool, owner: UUID? = nil) async -> Bool {
        guard let sessionID else { return false }
        if let owner, !ownsReply(owner) { return false }
        let expectedOwner = replyOwner
        let requestID = UUID()
        historyRequestID = requestID
        @MainActor func isCurrent() -> Bool {
            self.sessionID == sessionID && replyOwner == expectedOwner
                && historyRequestID == requestID && !Task.isCancelled
        }
        isLoadingHistory = messages.isEmpty
        historyLoadFailed = false
        defer { if historyRequestID == requestID { isLoadingHistory = false } }
        do {
            let remote = try await replyAPI.fetchMessages(sessionID: sessionID, limit: 100, beforeID: nil, aroundID: nil)
            guard isCurrent() else { return false }
            let withThinking = preserveLocalThinking(in: remote)
            let merged = mergeRemoteHistory(withThinking)
            let awaitingIDs = Set(messages.filter(\.isAwaitingReply).map(\.id))
            messages = merged
            revealLandedReplies(previouslyAwaiting: awaitingIDs)
            searchCorpus = mergeMessages(searchCorpus, with: merged)
            isShowingCachedMessages = false
            statusText = nil
            await cache.save(Self.cacheable(merged), sessionID: sessionID)
            guard isCurrent() else { return false }
            let throughID = merged.last(where: { $0.sender == .ke })?.serverID
            // 125 修：回话整轮攥着后台时间，她不在时也会写完、拉记录——这时还没看，不告诉服务器看过了；
            // 回到前台（resumeFromForeground）再补上。
            if enteredBackground || UIApplication.shared.applicationState == .background {
                deferredSeen = (sessionID, throughID)
            } else {
                deferredSeen = nil
                Task { try? await replyAPI.markSeen(sessionID: sessionID, throughID: throughID) }
            }
            // Notification-service completion must never hold the reply in a sending state.
            Task { await ChatNotificationCoordinator.shared.clearBadgeIfActive() }
            return isCurrent()
        } catch APIError.unauthorized {
            guard isCurrent() else { return false }
            phase = .needsLogin
        } catch {
            guard isCurrent() else { return false }
            isShowingCachedMessages = !messages.isEmpty
            historyLoadFailed = messages.isEmpty
            if showFailure || !messages.isEmpty {
                statusText = messages.isEmpty
                    ? "聊天记录暂时没有拉下来。"
                    : "现在显示本地记录，网络恢复后会自动更新。"
            }
        }
        return false
    }

    private func performSend(
        text: String,
        sessionID: Int,
        clientID: String,
        userLocalID: String,
        assistantLocalID: String,
        attachments: [ChatAttachment],
        reduceMotion: Bool,
        retryCount: Int,
        owner: UUID
    ) async {
        guard ownsReply(owner) else { return }
        var didComplete = false
        var completionStatus: String?
        var completionError: String?
        var completionRetryable = false
        var retryScheduled = false
        var serverErrorMessage: String?
        /// 121：柯的正文一路收着，不往气泡里写——写完（done）那一刻才整条放上去。
        /// 断线重接是新的一轮 performSend，从头再收，不会把前一轮的半截接在后面。
        var replyText = ""
        var pendingThinking = ""
        var lastPublish = Date.distantPast

        func flushBufferedEvents() {
            guard ownsReply(owner) else { return }
            guard !pendingThinking.isEmpty else { return }
            let thinkingDelta = pendingThinking
            pendingThinking = ""
            updateMessage(id: assistantLocalID) {
                $0.thoughtSummary = ($0.thoughtSummary ?? "") + thinkingDelta
            }
            streamRevision += 1
            lastPublish = .now
        }

        do {
            let stream = try await replyAPI.streamMessage(
                text: text,
                sessionID: sessionID,
                clientMessageID: clientID,
                model: selectedModel,
                attachments: attachments
            )

            guard ownsReply(owner) else { return }
            noteStreamActivity(owner)
            defer { endStreamWatch(owner) }
            for try await event in stream {
                guard ownsReply(owner) else { return }
                noteStreamActivity(owner)
                switch event {
                case .keepAlive:
                    continue

                case let .receipt(userMessageID, jobID, bedroom):
                    if let jobID {
                        activeJobID = jobID
                    }
                    // 137：服务器收到了，这句之后不会再放回输入框
                    composerClientIDs.remove(clientID)
                    updateMessage(id: userLocalID) {
                        $0.serverID = userMessageID ?? $0.serverID
                        $0.deliveryState = .sent
                    }
                    sendHaptics.acknowledge(clientID: clientID, serverID: userMessageID)
                    applyBedroom(bedroom)

                case let .text(delta):
                    // 121：只收不显示。气泡不再跟着字数一点点长、写完再被切开（她说的「抖动」）。
                    replyText += delta

                case let .thinkingDelta(delta):
                    pendingThinking += delta
                    if Date.now.timeIntervalSince(lastPublish) >= 0.05 {
                        flushBufferedEvents()
                    }

                case let .thoughtNote(summary):
                    flushBufferedEvents()
                    updateMessage(id: assistantLocalID) { $0.thoughtNote = summary }
                    streamRevision += 1

                case let .toolRun(toolRun):
                    flushBufferedEvents()
                    updateMessage(id: assistantLocalID) { message in
                        var runs = message.toolRuns ?? []
                        if let index = runs.firstIndex(where: { $0.id == toolRun.id }) {
                            runs[index] = toolRun
                        } else {
                            runs.append(toolRun)
                        }
                        message.toolRuns = runs
                    }
                    streamRevision += 1

                case let .completed(
                    assistantMessageID,
                    bedroom,
                    status,
                    error,
                    retryable,
                    scheduled,
                    segments
                ):
                    flushBufferedEvents()
                    didComplete = true
                    endStreamWatch(owner)
                    completionStatus = status ?? (assistantMessageID == nil ? "error" : "done")
                    completionError = error ?? serverErrorMessage
                    completionRetryable = retryable
                    retryScheduled = scheduled
                    if assistantMessageID != nil {
                        settledReplyClientIDs.insert(clientID)
                        // 121：整条一次放上去，气泡照服务器切好的分；服务器没给（旧服务器）才用本机切法。
                        let landed = Self.landedReply(text: replyText, segments: segments)
                        if landed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // 这一轮流里一个字都没收到（重接时只补了一个 done）：不放一条空的上去，
                            // 记住 serverID 接着等，紧跟着拉回来的记录会在原位整条换上、照样一个个冒出来。
                            updateMessage(id: assistantLocalID) { $0.serverID = assistantMessageID ?? $0.serverID }
                        } else {
                            updateMessage(id: assistantLocalID) {
                                $0.serverID = assistantMessageID ?? $0.serverID
                                $0.text = landed.text
                                $0.segments = landed.segments
                                $0.isStreaming = false
                                $0.deliveryState = .sent
                            }
                            if let completed = messages.first(where: { $0.id == assistantLocalID }) {
                                stageSegments(for: completed, reduceMotion: reduceMotion || landsWhole)
                            }
                            streamRevision += 1
                        }
                    } else if status == "merged" {
                        // 这一条已经并进她后面补发的那条，由那条一起回；空位直接收起，不算失败。
                        removeEmptyAssistant(id: assistantLocalID)
                    } else {
                        updateMessage(id: assistantLocalID) {
                            $0.isStreaming = false
                            $0.deliveryState = scheduled ? .waiting : .failed
                        }
                    }
                    applyBedroom(bedroom)

                case let .serverError(message):
                    // 服务端随后还会给出最终任务状态。先记下原因，不能在这里提前
                    // 抛错，否则 waiting_retry / retryable 会被旧逻辑吞掉。
                    serverErrorMessage = message
                }
            }

            guard ownsReply(owner) else { return }
            guard didComplete else { throw APIError.streamClosed }
            if completionStatus == "waiting_retry" || retryScheduled {
                updateMessage(id: assistantLocalID) {
                    $0.isStreaming = false
                    $0.deliveryState = .waiting
                }
                statusText = "线路忙，服务器会自动再接一次。退出 App 也没关系。"
                if let activeJobID {
                    await pollForCompletion(
                        jobID: activeJobID,
                        fallbackClientID: clientID,
                        fallbackUserMessageID: messages.first(where: { $0.id == userLocalID })?.serverID,
                        assistantLocalID: assistantLocalID, owner: owner
                    )
                } else {
                    isSending = false
                    markReplyFailed(
                        jobID: "",
                        clientMessageID: clientID,
                        userMessageID: messages.first(where: { $0.id == userLocalID })?.serverID,
                        assistantLocalID: assistantLocalID,
                        message: completionError ?? "线路没有接稳，柯还没生成完整回复。",
                        retryable: false
                    )
                }
                return
            }
            if completionStatus == "error" {
                if let activeJobID {
                    await pollForCompletion(
                        jobID: activeJobID,
                        fallbackClientID: clientID,
                        fallbackUserMessageID: messages.first(where: { $0.id == userLocalID })?.serverID,
                        assistantLocalID: assistantLocalID, owner: owner
                    )
                } else {
                    isSending = false
                    statusText = nil
                    markReplyFailed(
                        jobID: "",
                        clientMessageID: clientID,
                        userMessageID: messages.first(where: { $0.id == userLocalID })?.serverID,
                        assistantLocalID: assistantLocalID,
                        message: completionError ?? "线路没有接稳，柯还没生成完整回复。",
                        retryable: completionRetryable
                    )
                }
                return
            }
            statusText = nil
            replyFailure = nil
            // 119：任务 id 留到记录拉完再清。拉记录途中被切到后台再回来，接回会去问这个任务，
            // 而不是拿同一个 clientID 再发一遍（再发会把整段正文又追加一遍，然后被切成好几截）。
            await refreshHistory(showFailure: false, owner: owner)
            guard ownsReply(owner) else { return }
            activeJobID = nil
            isSending = false
            replyCompleted()

        } catch APIError.unauthorized {
            guard ownsReply(owner) else { return }
            flushBufferedEvents()
            isSending = false
            markFailed(userLocalID: userLocalID, assistantLocalID: assistantLocalID)
            failedSends[clientID] = attachments
            phase = .needsLogin

        } catch {
            guard ownsReply(owner) else { return }
            flushBufferedEvents()
            if let activeJobID {
                // 119：半截正文不提前当成写完（isStreaming=false 会把半截按空行切开），
                // 等服务器那条完整的拉回来一次换上。
                updateMessage(id: assistantLocalID) { $0.deliveryState = .waiting }
                statusText = "连接断了一下，柯的话还在服务器写，写完会自动接回来。"
                await pollForCompletion(
                    jobID: activeJobID,
                    fallbackClientID: clientID,
                    fallbackUserMessageID: messages.first(where: { $0.id == userLocalID })?.serverID,
                    assistantLocalID: assistantLocalID, owner: owner
                )
            } else if retryCount == 0 {
                statusText = "连接断了一下，正在用同一条消息接回…"
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard ownsReply(owner) else { return }
                await performSend(
                    text: text,
                    sessionID: sessionID,
                    clientID: clientID,
                    userLocalID: userLocalID,
                    assistantLocalID: assistantLocalID,
                    attachments: attachments,
                    reduceMotion: reduceMotion,
                    retryCount: 1, owner: owner
                )
            } else {
                isSending = false
                markFailed(userLocalID: userLocalID, assistantLocalID: assistantLocalID)
                statusText = "这句没有发稳。网络好了，长按它可以重发。"
                pendingAttachments = mergeAttachments(pendingAttachments, with: attachments)
                // 137：重发时原样带上这几个附件；从输入框发的，字也放回输入框（她输入框空着才放）
                failedSends[clientID] = attachments
                if composerClientIDs.contains(clientID), !text.isEmpty {
                    restoredDraft = RestoredDraft(messageID: userLocalID, text: text)
                }
                // 137：没发稳的这句存进缓存，App 被关掉再打开还在
                await cache.save(Self.cacheable(messages), sessionID: sessionID)
            }
        }
    }

    func retryFailedReply(reduceMotion: Bool = false) async {
        guard let sessionID,
              let failure = replyFailure,
              failure.canRetry,
              !isSending,
              !failure.jobID.isEmpty,
              !failure.clientMessageID.isEmpty else { return }

        let userLocalID = messages.first(where: {
            failure.userMessageID != nil && $0.serverID == failure.userMessageID
        })?.id ?? "user-retry-\(failure.jobID)"
        let assistantLocalID = "assistant-retry-\(failure.jobID)"
        if !messages.contains(where: { $0.id == assistantLocalID }) {
            messages.append(Message(
                id: assistantLocalID,
                clientID: failure.clientMessageID,
                sender: .ke,
                text: "",
                time: .now,
                isStreaming: true,
                deliveryState: .sending
            ))
        }

        isSending = true
        statusText = "正在接回刚才那条，不会重复发送你的消息。"
        replyFailure = nil
        activeJobID = failure.jobID
        activeStreamClientID = failure.clientMessageID
        let owner = UUID()
        replyOwner = owner
        recoveringJobID = nil
        pendingReply = PendingReply(clientID: failure.clientMessageID, userLocalID: userLocalID,
                                    assistantLocalID: assistantLocalID, text: "", attachments: [], reduceMotion: reduceMotion)
        let task = Task { [self] in
            await performSend(text: "", sessionID: sessionID, clientID: failure.clientMessageID,
                              userLocalID: userLocalID, assistantLocalID: assistantLocalID,
                              attachments: [], reduceMotion: reduceMotion, retryCount: 0, owner: owner)
            guard ownsReply(owner) else { return }
            activeStreamClientID = nil
            await recoverPendingReceipts(owner: owner)
            guard ownsReply(owner) else { return }
            await drainQueuedFollowUps(owner: owner)
            finishReplyTask(owner)
        }
        await runReplyTask(task)
    }

    func dismissReplyFailure() {
        replyFailure = nil
    }

    private func recoverActiveJobsIfNeeded() async {
        guard sessionID != nil, replyTask == nil, activeStreamClientID == nil else { return }
        let owner = UUID()
        replyOwner = owner
        // 上一轮已经结束（replyTask 为空），它留下的轮询标记不能挡住这一轮，否则 isSending 没人清。
        recoveringJobID = nil
        recoveryOwner = owner
        recoveryStartedAt = .now
        let task = Task { [self] in
            await recoverReply(owner: owner)
            guard ownsReply(owner) else { return }
            activeStreamClientID = nil
            await recoverPendingReceipts(owner: owner)
            guard ownsReply(owner) else { return }
            await drainQueuedFollowUps(owner: owner)
            finishReplyTask(owner)
        }
        await runReplyTask(task)
    }

    private func recoverReply(owner: UUID) async {
        guard let sessionID, ownsReply(owner) else { return }
        // Completed jobs disappear from the active list. Ask for the known job directly.
        if let jobID = activeJobID {
            isSending = true
            await pollForCompletion(jobID: jobID,
                                    fallbackClientID: pendingReply?.clientID ?? "",
                                    assistantLocalID: pendingReply?.assistantLocalID, owner: owner)
            return
        }
        recoveryProbeID = owner
        defer { if recoveryProbeID == owner { recoveryProbeID = nil } }
        do {
            let jobs = try await replyAPI.activeJobs(sessionID: sessionID, includeRecentFailures: true)
            guard ownsReply(owner) else { return }
            let job = pendingReply.map { pending in
                jobs.first { $0.clientMessageID == pending.clientID }
            } ?? jobs.first
            if let job {
                activeJobID = job.id
                isSending = true
                await pollForCompletion(jobID: job.id,
                                        fallbackClientID: job.clientMessageID ?? "",
                                        fallbackUserMessageID: job.userMessageID,
                                        assistantLocalID: pendingReply?.assistantLocalID, owner: owner)
            } else if let pending = pendingReply,
                      messages.first(where: { $0.id == pending.userLocalID })?.serverID == nil {
                // No receipt before suspension: reuse the existing idempotency key and
                // original payload, never invent a new message or guess by matching text.
                // 119：已经有回执的（她那条有 serverID）说明服务器收到了、任务也不在进行中，
                // 只差拉记录；不能再发一遍。
                activeStreamClientID = pending.clientID
                await performSend(text: pending.text, sessionID: sessionID, clientID: pending.clientID,
                                  userLocalID: pending.userLocalID, assistantLocalID: pending.assistantLocalID,
                                  attachments: pending.attachments, reduceMotion: pending.reduceMotion,
                                  retryCount: 0, owner: owner)
            } else {
                // 121：她那条服务器收到了、任务也不在进行中——这一句已经写完（或并进了后面那条）。
                // 本机那个「发送中」的空位不再留着等，拉回来的记录里有完整的那条。
                if let pending = pendingReply { settledReplyClientIDs.insert(pending.clientID) }
                await refreshHistory(showFailure: false, owner: owner)
                guard ownsReply(owner) else { return }
                isSending = false
            }
        } catch APIError.unauthorized {
            guard ownsReply(owner) else { return }
            phase = .needsLogin
        } catch {
            guard ownsReply(owner) else { return }
            await refreshHistory(showFailure: false, owner: owner)
            // Keep pending IDs/drafts so another foreground or explicit refresh can retry.
        }
    }

    private func reconcile(_ job: ActiveChatJob, clientID: String, assistantLocalID: String?) {
        for index in messages.indices where messages[index].clientID == clientID && !clientID.isEmpty {
            if messages[index].sender == .me, let id = job.userMessageID {
                messages[index].serverID = id
                messages[index].deliveryState = .sent
            }
            // 119：只认 serverID，不改 isStreaming/正文。半截正文要是先标成写完，会先被切成几截，
            // 随后再被服务器那条完整的换掉——看起来就是「显示两遍又被切开」。
            // 拉回记录时按 serverID 在原位换成完整那条（沿用本机 id，见 mergeRemoteHistory）。
            if messages[index].sender == .ke, let id = job.assistantMessageID {
                messages[index].serverID = id
            }
        }
        if let assistantLocalID, let id = job.assistantMessageID {
            updateMessage(id: assistantLocalID) { $0.serverID = id }
        }
    }

    private func pollForCompletion(
        jobID: String,
        fallbackClientID: String = "",
        fallbackUserMessageID: Int? = nil,
        assistantLocalID: String? = nil,
        owner: UUID
    ) async {
        guard let sessionID, ownsReply(owner), recoveringJobID == nil else { return }
        recoveringJobID = jobID
        defer { if ownsReply(owner), recoveringJobID == jobID { recoveringJobID = nil } }

        for attempt in 0..<150 {
            guard ownsReply(owner) else { return }
            do {
                lastPollAt = .now
                let job = try await replyAPI.chatJob(id: jobID, sessionID: sessionID)
                guard ownsReply(owner) else { return }
                let clientID = job.clientMessageID ?? fallbackClientID
                reconcile(job, clientID: clientID, assistantLocalID: assistantLocalID)
                switch job.status {
                case "done", "merged":
                    if !clientID.isEmpty { settledReplyClientIDs.insert(clientID) }
                    if job.status == "merged" {
                        messages.removeAll { $0.sender == .ke && $0.clientID == clientID && $0.serverID == nil }
                    }
                    let fetched = await refreshHistory(showFailure: true, owner: owner)
                    guard ownsReply(owner) else { return }
                    if fetched {
                        isSending = false
                        activeJobID = nil
                        statusText = nil
                        replyFailure = nil
                        queuedFollowUps.removeAll { $0.jobID == jobID }
                        replyCompleted()
                        return
                    }
                case "waiting_retry":
                    statusText = "线路忙，服务器会自动再接一次。退出 App 也没关系。"
                case "error":
                    await refreshHistory(showFailure: false, owner: owner)
                    guard ownsReply(owner) else { return }
                    isSending = false
                    activeJobID = nil
                    statusText = nil
                    if let assistantLocalID { removeEmptyAssistant(id: assistantLocalID) }
                    presentReplyFailure(job, fallbackClientID: fallbackClientID,
                                        fallbackUserMessageID: fallbackUserMessageID)
                    return
                default:
                    statusText = "柯还有一句话在写，写完会自动接回来。"
                    if attempt == 0 { await refreshHistory(showFailure: false, owner: owner) }
                }
            } catch APIError.unauthorized {
                guard ownsReply(owner) else { return }
                isSending = false
                phase = .needsLogin
                return
            } catch {
                guard ownsReply(owner) else { return }
                // Network failure leaves the current local reply and known job recoverable.
            }
            // 125：头 20 问隔 1 秒（柯一般十几秒内写完，写完到落下来不再白等 2 秒），之后隔 2 秒。
            // 这一下睡可以被叫醒（回前台、点推送）：马上再问，不把这一轮掐断重来。
            let nap = Task<Void, Never> { try? await Task.sleep(nanoseconds: attempt < 20 ? 1_000_000_000 : 2_000_000_000) }
            pollNap = nap
            await withTaskCancellationHandler { await nap.value } onCancel: { nap.cancel() }
            if pollNap == nap { pollNap = nil }
            if Task.isCancelled { return }
        }
        guard ownsReply(owner) else { return }
        isSending = false
        if let assistantLocalID {
            updateMessage(id: assistantLocalID) { $0.isStreaming = false; $0.deliveryState = .waiting }
        }
        statusText = "回复仍留在服务器，下次回到 App 会继续接回。"
    }

    private func applyBedroom(_ bedroom: Bool?) {
        guard let bedroom else { return }
        Theme.shared.applyServerSignal(bedroom: bedroom)
    }

    func visibleSegmentCount(for message: Message) -> Int? {
        visibleSegmentCounts[message.bubbleRevealKey]
    }

    /// 127：只读，给时间线条目缓存当钥匙用（气泡一个个冒出来时它会变）
    var segmentRevealCounts: [String: Int] { visibleSegmentCounts }

    /// 121：写完那一刻放上去的正文。气泡以服务器切好的为准；服务器没给才退回本机切法（segments 为 nil）。
    /// 一路收来的原文为空（重接时服务器只补了一个 done）就用切好的气泡拼回正文，复制出来也是整条。
    static func landedReply(text: String, segments: [String]?) -> (text: String, segments: [String]?) {
        let server = (segments ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !server.isEmpty else { return (text, nil) }
        let streamed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (streamed.isEmpty ? server.joined(separator: "\n\n") : text, server)
    }

    /// 121：回前台、点推送、轮询接回——原来在等的那句换成了服务器那条完整的，也照样一个个冒出来，
    /// 和流里直接写完的一个样子。已经冒过（或正在冒）的那几条不重来：SSE 写完后紧跟着的那次拉记录，
    /// 本机那条早就不是「在等」了，这里不会碰它。
    private func revealLandedReplies(previouslyAwaiting awaitingIDs: Set<String>) {
        guard !awaitingIDs.isEmpty else { return }
        var landed = false
        let whole = landsWhole
        for message in messages where awaitingIDs.contains(message.id) && !message.isAwaitingReply {
            landed = true
            guard segmentRevealTasks[message.bubbleRevealKey] == nil else { continue }
            stageSegments(
                for: message,
                reduceMotion: whole || (pendingReply?.reduceMotion ?? false) || UIAccessibility.isReduceMotionEnabled
            )
        }
        // 占位那一行换成了气泡：让时间线把它当成新内容，跟着落到最底（她本来就在看最新时）。
        if landed { streamRevision += 1 }
    }

    /// 125：这句落下来时她没在看（App 在后台），或者她刚从后台回来、点了推送（横幅里已经读过）：
    /// 整条一次放上，不再隔 0.4 秒一个个冒——那只像还在等。
    private var landsWhole: Bool {
        enteredBackground || landWholeUntil.map { Date.now < $0 } == true
    }

    private func stageSegments(for message: Message, reduceMotion: Bool) {
        let key = message.bubbleRevealKey
        segmentRevealTasks[key]?.cancel()
        segmentRevealTasks[key] = nil
        guard !reduceMotion, message.bubbleSegments.count > 1 else {
            visibleSegmentCounts.removeValue(forKey: key)
            return
        }

        let total = message.bubbleSegments.count
        // 128：间隔按气泡个数收紧，加起来不超过半秒
        let interval = Theme.shared.motion.splitBubbleInterval(forCount: total)
        visibleSegmentCounts[key] = 1
        segmentRevealTasks[key] = Task { [weak self] in
            guard let self else { return }
            for count in 2...total {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                visibleSegmentCounts[key] = count
            }
            visibleSegmentCounts.removeValue(forKey: key)
            segmentRevealTasks[key] = nil
        }
    }

    private func updateMessage(id: String, mutate: (inout Message) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[index])
    }

    private func prepareForSession(_ newSessionID: Int) {
        guard sessionID != newSessionID else { return }
        abandonReplyConnection()
        pendingReply = nil
        pendingReceipts.removeAll()
        queuedFollowUps.removeAll()
        for task in segmentRevealTasks.values { task.cancel() }
        segmentRevealTasks.removeAll()
        visibleSegmentCounts.removeAll()
        messages.removeAll()
        searchCorpus.removeAll()
        historyLoadFailed = false
        isLoadingHistory = false
        isShowingCachedMessages = false
        statusText = nil
        activeJobID = nil
        recoveringJobID = nil
        recoveryProbeID = nil
        recoveryOwner = nil
        recoveryStartedAt = nil
        settledReplyClientIDs.removeAll()
        failedSends.removeAll()
        composerClientIDs.removeAll()
        restoredDraft = nil
        activeStreamClientID = nil
        isSending = false
        sessionID = newSessionID
    }

    private func preserveLocalThinking(in remote: [Message]) -> [Message] {
        let localByServerID = Dictionary(
            messages.compactMap { message -> (Int, Message)? in
                guard let serverID = message.serverID else { return nil }
                return (serverID, message)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return remote.map { message in
            guard let serverID = message.serverID,
                  let local = localByServerID[serverID] else { return message }
            var preserved = message
            if nonBlank(preserved.thoughtSummary) == nil {
                preserved.thoughtSummary = nonBlank(local.thoughtSummary)
            }
            if nonBlank(preserved.thoughtNote) == nil {
                preserved.thoughtNote = nonBlank(local.thoughtNote)
            }
            if nonBlank(preserved.thoughtSummaryRaw) == nil {
                preserved.thoughtSummaryRaw = nonBlank(local.thoughtSummaryRaw)
            }
            return preserved
        }
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func mergeRemoteHistory(_ remote: [Message]) -> [Message] {
        let remoteServerIDs = Set(remote.compactMap(\.serverID))
        // 113 她：「柯发消息还是会往下掉一下 回来」。回完一句会重新拉记录，服务器那份换了 id，
        // 列表认不出是同一条，整个重排一次就跳。同一条（serverID 一样）沿用本机原来的 id。
        var localIDs: [Int: String] = [:]
        for local in messages {
            if let serverID = local.serverID, localIDs[serverID] == nil { localIDs[serverID] = local.id }
        }
        var merged = remote.map { item -> Message in
            guard let serverID = item.serverID, let localID = localIDs[serverID], localID != item.id else { return item }
            var kept = item
            kept.id = localID
            return kept
        }
        for local in messages {
            if let serverID = local.serverID, remoteServerIDs.contains(serverID) {
                continue
            }
            // 119：这一句服务器已经写完，本机没对上 serverID 的柯的气泡（半截、重试留下的）一律不留，
            // 只显示服务器那条。
            if local.sender == .ke, local.serverID == nil, let clientID = local.clientID,
               settledReplyClientIDs.contains(clientID) {
                continue
            }
            let belongsToActiveStream = local.clientID != nil
                && local.clientID == activeStreamClientID
            let needsPreserving = local.isStreaming
                || local.deliveryState != .sent
                || belongsToActiveStream
            if needsPreserving && !merged.contains(where: { $0.id == local.id }) {
                merged.append(local)
            }
        }
        return merged.sorted(by: messagePrecedes)
    }

    private func mergeMessages(_ current: [Message], with incoming: [Message]) -> [Message] {
        var values: [String: Message] = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for message in incoming { values[message.id] = message }
        return values.values.sorted(by: messagePrecedes)
    }

    private func messagePrecedes(_ lhs: Message, _ rhs: Message) -> Bool {
        if (lhs.serverTimeIsValid == false || rhs.serverTimeIsValid == false),
           let lhsServerID = lhs.serverID,
           let rhsServerID = rhs.serverID {
            return lhsServerID < rhsServerID
        }
        if lhs.time == rhs.time {
            return (lhs.serverID ?? 0) < (rhs.serverID ?? 0)
        }
        return lhs.time < rhs.time
    }

    private func mergeAttachments(
        _ current: [ChatAttachment],
        with incoming: [ChatAttachment]
    ) -> [ChatAttachment] {
        var values = current
        for attachment in incoming where !values.contains(where: { $0.url == attachment.url }) {
            values.append(attachment)
        }
        return Array(values.prefix(9))
    }

    private func presentReplyFailure(
        _ job: ActiveChatJob,
        fallbackClientID: String = "",
        fallbackUserMessageID: Int? = nil
    ) {
        let message = job.error?.trimmingCharacters(in: .whitespacesAndNewlines)
        replyFailure = ReplyFailure(
            jobID: job.id,
            clientMessageID: job.clientMessageID ?? fallbackClientID,
            userMessageID: job.userMessageID ?? fallbackUserMessageID,
            message: (message?.isEmpty == false)
                ? message!
                : "线路没有接稳，柯还没生成完整回复。",
            canRetry: job.retryable ?? false
        )
    }

    private func markReplyFailed(
        jobID: String,
        clientMessageID: String,
        userMessageID: Int?,
        assistantLocalID: String,
        message: String,
        retryable: Bool
    ) {
        removeEmptyAssistant(id: assistantLocalID)
        replyFailure = ReplyFailure(
            jobID: jobID,
            clientMessageID: clientMessageID,
            userMessageID: userMessageID,
            message: message,
            canRetry: retryable && !jobID.isEmpty && !clientMessageID.isEmpty
        )
    }

    private func removeEmptyAssistant(id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        if messages[index].text.isEmpty
            && nonBlank(messages[index].thoughtSummary) == nil
            && nonBlank(messages[index].thoughtNote) == nil {
            messages.remove(at: index)
        } else {
            messages[index].isStreaming = false
            messages[index].deliveryState = .failed
        }
    }

    private func markFailed(userLocalID: String, assistantLocalID: String) {
        updateMessage(id: userLocalID) { $0.deliveryState = .failed }
        if let index = messages.firstIndex(where: { $0.id == assistantLocalID }) {
            if messages[index].text.isEmpty
                && nonBlank(messages[index].thoughtSummary) == nil
                && nonBlank(messages[index].thoughtNote) == nil {
                messages.remove(at: index)
            } else {
                messages[index].isStreaming = false
                messages[index].deliveryState = .failed
            }
        }
    }
}
