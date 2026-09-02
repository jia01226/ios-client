import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {
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
    @Published var modelError: String?
    @Published var modelQuotaError: String?
    @Published var searchCorpus: [Message] = []
    @Published var isPreparingSearch = false
    @Published var searchError: String?
    @Published var isDeleting = false
    @Published var deleteError: String?
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var isUploading = false
    @Published var uploadingFileName: String?
    @Published var uploadError: String?
    @Published var canRetryUpload = false
    @Published var replyFailure: ReplyFailure?
    @Published private var visibleSegmentCounts: [String: Int] = [:]

    private let api = APIClient.shared
    private let cache = ChatCache.shared
    private var sessionID: Int?
    private var didBootstrap = false
    private var activeJobID: String?
    private var recoveringJobID: String?
    private var activeStreamClientID: String?
    private var recoveryProbeID: UUID?
    private var segmentRevealTasks: [String: Task<Void, Never>] = [:]
    private var failedUpload: AttachmentUploadPayload?
    private var lastModelQuotaLoad: Date?
    private var modelQuotaRequestRevision = 0

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
    }

    private var uiTestFixture: UITestFixture?
#endif

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-test-reply-failure") {
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
            selectedModel = "claude2-subscription-opus-5"
            modelGroups = [
                ChatModelGroup(
                    id: "claude_1", label: "Claude 1", available: true,
                    configured: true, message: nil
                ),
                ChatModelGroup(
                    id: "claude_2", label: "Claude 2", available: false,
                    configured: true, message: "额度冷却中"
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
                    id: "claude-subscription-opus-5", provider: "claude_subscription",
                    label: "Opus 5", description: "Claude Max 1 号账号",
                    group: "claude_subscription", family: "claude_1", available: true
                ),
                ChatModelOption(
                    id: "claude2-subscription-opus-5", provider: "claude_subscription",
                    label: "Opus 5", description: "Claude Max 2 号账号",
                    group: "claude_subscription", family: "claude_2", available: false
                ),
                ChatModelOption(
                    id: "codex-subscription:gpt-5.6-terra", provider: "codex_subscription",
                    label: "GPT-5.6 Terra", description: "ChatGPT 的 Codex 订阅额度",
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
                selectedGroup: "claude_2",
                currentRouteGroup: "claude_1",
                groups: [
                    ChatModelQuotaGroup(
                        id: "claude_1", label: "Claude 1", configured: true,
                        available: true, status: "available", usedPercent: nil,
                        remainingPercent: nil, resetAt: nil, stale: false,
                        source: "circuit_breaker", windows: []
                    ),
                    ChatModelQuotaGroup(
                        id: "claude_2", label: "Claude 2", configured: true,
                        available: false, status: "cooldown", usedPercent: nil,
                        remainingPercent: nil,
                        resetAt: Date.now.addingTimeInterval(3_600).timeIntervalSince1970,
                        stale: false,
                        source: "circuit_breaker", windows: []
                    ),
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
                Message(
                    id: "ui-test-reply-streaming-assistant",
                    sender: .ke,
                    text: "第一句先来到屏幕上，",
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
                    text: "长文正在接回来。",
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
            }
            phase = .ready
            var fixtureMessages: [Message] = []
            for index in 0..<7 {
                fixtureMessages.append(Message(
                    id: "ui-test-history-user-\(index)",
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
            "第二句接着流进同一个气泡，",
            "最后一句再慢慢说完。"
        ]

        for chunk in chunks {
            try? await Task.sleep(nanoseconds: 420_000_000)
            updateMessage(id: messageID) { $0.text += chunk }
            streamRevision += 1
        }

        updateMessage(id: messageID) {
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
        updateMessage(id: "ui-test-very-long-assistant") { $0.text = longText }
        streamRevision += 1
    }

    private func runUITestSendStream(messageID: String) async {
        let chunks = ["爸爸收到了。", "这次屏幕不会再乱跳。"]
        for chunk in chunks {
            try? await Task.sleep(nanoseconds: 360_000_000)
            updateMessage(id: messageID) { $0.text += chunk }
            streamRevision += 1
        }
        updateMessage(id: messageID) {
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
        loginError = nil
        defer { isLoggingIn = false }

        do {
            try await api.login(passcode: passcode)
            let active = try await api.activeSession()
            prepareForSession(active.id)
            selectedModel = active.model
            phase = .ready
            CompanionPermissionCoordinator.shared.sessionDidBecomeReady()
            await loadCache(sessionID: active.id)
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
        // 原 SSE 仍是这条回复的唯一所有者时，不并行启动 job polling。
        guard activeStreamClientID == nil else { return }
        await recoverActiveJobsIfNeeded()
        guard activeStreamClientID == nil else { return }
        if recoveringJobID == nil {
            await refreshHistory(showFailure: false)
        }
    }

    func retryHistory() async {
        await refreshHistory(showFailure: true)
    }

    func send(_ text: String, reduceMotion: Bool = false) async {
        guard let sessionID, !isSending else { return }
        let attachments = pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty else { return }

        isSending = true
        statusText = nil
        replyFailure = nil
        activeJobID = nil
        // Invalidate any foreground recovery probe that is currently awaiting the network.
        recoveryProbeID = nil
        pendingAttachments = []

        let clientID = "ios-\(UUID().uuidString.lowercased())"
        let userLocalID = "user-\(clientID)"
        let assistantLocalID = "assistant-\(clientID)"
        activeStreamClientID = clientID
        defer {
            if activeStreamClientID == clientID {
                activeStreamClientID = nil
            }
        }

        messages.append(
            Message(
                id: userLocalID,
                clientID: clientID,
                sender: .me,
                text: text,
                time: .now,
                attachments: attachments,
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
            return
        }
#endif

        await performSend(
            text: text,
            sessionID: sessionID,
            clientID: clientID,
            userLocalID: userLocalID,
            assistantLocalID: assistantLocalID,
            attachments: attachments,
            reduceMotion: reduceMotion,
            retryCount: 0
        )
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
            if selectedModel == nil { selectedModel = catalog.default }
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
        modelQuotaError = nil
        if force {
            modelQuotaCatalog = nil
        }
        defer {
            if requestRevision == modelQuotaRequestRevision {
                isLoadingModelQuotas = false
            }
        }
        do {
            let catalog = try await api.fetchModelQuotas(sessionID: sessionID)
            guard requestRevision == modelQuotaRequestRevision else { return }
            modelQuotaCatalog = catalog
            lastModelQuotaLoad = Date()
        } catch {
            guard requestRevision == modelQuotaRequestRevision else { return }
            modelQuotaError = "额度暂时没读到，点刷新再试。"
        }
    }

    func selectModel(_ model: String) async {
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
        guard let sessionID, !isSelectingModel else { return }
        isSelectingModel = true
        modelError = nil
        defer { isSelectingModel = false }
        do {
            let active = try await api.selectModel(sessionID: sessionID, model: model)
            selectedModel = active.model ?? model
            modelQuotaCatalog = nil
            modelQuotaError = nil
            await loadModelQuotas(force: true)
        } catch {
            modelError = error.localizedDescription
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
        if let sessionID { await cache.save(messages, sessionID: sessionID) }
        return deleted
    }

    private func connect() async {
        if let snapshot = await cache.loadLatest() {
            prepareForSession(snapshot.sessionID)
            messages = snapshot.messages
            isShowingCachedMessages = true
            phase = .ready
            statusText = "正在接回服务器…"
        }

        do {
            let active = try await api.activeSession()
            prepareForSession(active.id)
            selectedModel = active.model
            CompanionPermissionCoordinator.shared.sessionDidBecomeReady()
            await loadCache(sessionID: active.id)
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
        guard self.sessionID == sessionID, !cached.isEmpty else { return }
        // Cache I/O may finish after send() has created local bubbles. Always merge
        // so streaming, waiting and failed local bubbles remain addressable.
        messages = mergeRemoteHistory(cached)
        if !messages.isEmpty {
            isShowingCachedMessages = true
        }
    }

    private func refreshHistory(showFailure: Bool) async {
        guard let sessionID else { return }
        isLoadingHistory = messages.isEmpty
        historyLoadFailed = false
        defer { isLoadingHistory = false }
        do {
            let remote = try await api.fetchMessages(sessionID: sessionID)
            guard self.sessionID == sessionID else { return }
            let withThinking = preserveLocalThinking(in: remote)
            let merged = mergeRemoteHistory(withThinking)
            messages = merged
            searchCorpus = mergeMessages(searchCorpus, with: merged)
            isShowingCachedMessages = false
            statusText = nil
            await cache.save(merged, sessionID: sessionID)
            try? await api.markSeen(
                sessionID: sessionID,
                throughID: merged.last(where: { $0.sender == .ke })?.serverID
            )
        } catch APIError.unauthorized {
            phase = .needsLogin
        } catch {
            isShowingCachedMessages = !messages.isEmpty
            historyLoadFailed = messages.isEmpty
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
        attachments: [ChatAttachment],
        reduceMotion: Bool,
        retryCount: Int
    ) async {
        var didComplete = false
        var completionStatus: String?
        var completionError: String?
        var completionRetryable = false
        var retryScheduled = false
        var serverErrorMessage: String?
        var pendingText = ""
        var pendingThinking = ""
        var lastPublish = Date.distantPast

        func flushBufferedEvents() {
            guard !pendingText.isEmpty || !pendingThinking.isEmpty else { return }
            let textDelta = pendingText
            let thinkingDelta = pendingThinking
            pendingText = ""
            pendingThinking = ""
            updateMessage(id: assistantLocalID) {
                $0.text += textDelta
                if !thinkingDelta.isEmpty {
                    $0.thoughtSummary = ($0.thoughtSummary ?? "") + thinkingDelta
                }
            }
            streamRevision += 1
            lastPublish = .now
        }

        do {
            let stream = try await api.streamMessage(
                text: text,
                sessionID: sessionID,
                clientMessageID: clientID,
                model: selectedModel,
                attachments: attachments
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
                    pendingText += delta
                    if Date.now.timeIntervalSince(lastPublish) >= 0.05 {
                        flushBufferedEvents()
                    }

                case let .thinkingDelta(delta):
                    pendingThinking += delta
                    if Date.now.timeIntervalSince(lastPublish) >= 0.05 {
                        flushBufferedEvents()
                    }

                case let .thoughtNote(summary):
                    flushBufferedEvents()
                    updateMessage(id: assistantLocalID) { $0.thoughtNote = summary }
                    streamRevision += 1

                case let .completed(
                    assistantMessageID,
                    bedroom,
                    status,
                    error,
                    retryable,
                    scheduled
                ):
                    flushBufferedEvents()
                    didComplete = true
                    completionStatus = status ?? (assistantMessageID == nil ? "error" : "done")
                    completionError = error ?? serverErrorMessage
                    completionRetryable = retryable
                    retryScheduled = scheduled
                    if assistantMessageID != nil {
                        updateMessage(id: assistantLocalID) {
                            $0.serverID = assistantMessageID ?? $0.serverID
                            $0.isStreaming = false
                            $0.deliveryState = .sent
                        }
                        if let completed = messages.first(where: { $0.id == assistantLocalID }) {
                            stageSegments(for: completed, reduceMotion: reduceMotion)
                        }
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
                        assistantLocalID: assistantLocalID
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
                        assistantLocalID: assistantLocalID
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
            activeJobID = nil
            statusText = nil
            replyFailure = nil
            await refreshHistory(showFailure: false)
            isSending = false
            CompanionPermissionCoordinator.shared.conversationDidComplete()

        } catch APIError.unauthorized {
            flushBufferedEvents()
            isSending = false
            markFailed(userLocalID: userLocalID, assistantLocalID: assistantLocalID)
            phase = .needsLogin

        } catch {
            flushBufferedEvents()
            if let activeJobID {
                updateMessage(id: assistantLocalID) {
                    $0.isStreaming = false
                    $0.deliveryState = .waiting
                }
                statusText = "连接断了一下，柯的话还在服务器写，写完会自动接回来。"
                await pollForCompletion(
                    jobID: activeJobID,
                    fallbackClientID: clientID,
                    fallbackUserMessageID: messages.first(where: { $0.id == userLocalID })?.serverID,
                    assistantLocalID: assistantLocalID
                )
            } else if retryCount == 0 {
                statusText = "连接断了一下，正在用同一条消息接回…"
                try? await Task.sleep(nanoseconds: 800_000_000)
                await performSend(
                    text: text,
                    sessionID: sessionID,
                    clientID: clientID,
                    userLocalID: userLocalID,
                    assistantLocalID: assistantLocalID,
                    attachments: attachments,
                    reduceMotion: reduceMotion,
                    retryCount: 1
                )
            } else {
                isSending = false
                markFailed(userLocalID: userLocalID, assistantLocalID: assistantLocalID)
                statusText = "这句没有发稳。内容留在这里，网络恢复后可以再发。"
                pendingAttachments = mergeAttachments(pendingAttachments, with: attachments)
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
        defer {
            if activeStreamClientID == failure.clientMessageID {
                activeStreamClientID = nil
            }
        }
        await performSend(
            text: "",
            sessionID: sessionID,
            clientID: failure.clientMessageID,
            userLocalID: userLocalID,
            assistantLocalID: assistantLocalID,
            attachments: [],
            reduceMotion: reduceMotion,
            retryCount: 0
        )
    }

    func dismissReplyFailure() {
        replyFailure = nil
    }

    private func recoverActiveJobsIfNeeded() async {
        guard let sessionID,
              recoveringJobID == nil,
              activeStreamClientID == nil,
              recoveryProbeID == nil else { return }
        let probeID = UUID()
        recoveryProbeID = probeID
        defer {
            if recoveryProbeID == probeID {
                recoveryProbeID = nil
            }
        }
        do {
            let jobs = try await api.activeJobs(
                sessionID: sessionID,
                includeRecentFailures: true
            )
            // send() may have started while activeJobs was in flight. A stale probe
            // must never clear its state or start a second polling owner.
            guard recoveryProbeID == probeID,
                  activeStreamClientID == nil else { return }
            guard let job = jobs.first else {
                isSending = false
                return
            }
            if job.status == "error" {
                isSending = false
                statusText = nil
                presentReplyFailure(job)
                return
            }
            isSending = true
            statusText = job.status == "waiting_retry"
                ? "线路忙，服务器会自动再接一次。退出 App 也没关系。"
                : "柯还有一句话在写，写完会自动接回来。"
            await pollForCompletion(
                jobID: job.id,
                fallbackClientID: job.clientMessageID ?? "",
                fallbackUserMessageID: job.userMessageID
            )
        } catch APIError.unauthorized {
            phase = .needsLogin
        } catch {
            // 前台恢复失败不覆盖已经显示的聊天记录。
        }
    }

    private func pollForCompletion(
        jobID: String,
        fallbackClientID: String = "",
        fallbackUserMessageID: Int? = nil,
        assistantLocalID: String? = nil
    ) async {
        guard let sessionID, recoveringJobID == nil else { return }
        recoveringJobID = jobID
        defer {
            recoveringJobID = nil
            activeJobID = nil
        }

        for _ in 0..<150 {
            if Task.isCancelled { break }
            do {
                let job = try await api.chatJob(id: jobID, sessionID: sessionID)
                switch job.status {
                case "done":
                    await refreshHistory(showFailure: true)
                    isSending = false
                    statusText = nil
                    replyFailure = nil
                    CompanionPermissionCoordinator.shared.conversationDidComplete()
                    return
                case "waiting_retry":
                    statusText = "线路忙，服务器会自动再接一次。退出 App 也没关系。"
                case "error":
                    await refreshHistory(showFailure: false)
                    isSending = false
                    statusText = nil
                    if let assistantLocalID {
                        removeEmptyAssistant(id: assistantLocalID)
                    }
                    presentReplyFailure(
                        job,
                        fallbackClientID: fallbackClientID,
                        fallbackUserMessageID: fallbackUserMessageID
                    )
                    return
                default:
                    statusText = "柯还有一句话在写，写完会自动接回来。"
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

    func visibleSegmentCount(for message: Message) -> Int? {
        visibleSegmentCounts[message.bubbleRevealKey]
    }

    private func stageSegments(for message: Message, reduceMotion: Bool) {
        let key = message.bubbleRevealKey
        segmentRevealTasks[key]?.cancel()
        guard !reduceMotion, message.bubbleSegments.count > 1 else {
            visibleSegmentCounts.removeValue(forKey: key)
            return
        }

        let total = message.bubbleSegments.count
        visibleSegmentCounts[key] = 1
        segmentRevealTasks[key] = Task { [weak self] in
            guard let self else { return }
            for count in 2...total {
                try? await Task.sleep(
                    nanoseconds: UInt64(Theme.shared.motion.splitBubbleInterval * 1_000_000_000)
                )
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
        var merged = remote
        for local in messages {
            if let serverID = local.serverID, remoteServerIDs.contains(serverID) {
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
