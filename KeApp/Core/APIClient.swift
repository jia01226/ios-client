import Foundation
import EventSource
import OSLog

enum APIError: LocalizedError {
    case badURL
    case unauthorized
    case badStatus(Int, String)
    case invalidResponse
    case decoding(Error)
    case transport(Error)
    case uploadTimedOut
    case streamClosed
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "服务器地址不对"
        case .unauthorized:
            return "需要重新登录"
        case let .badStatus(code, message):
            return message.isEmpty ? "服务器返回 HTTP \(code)" : message
        case .invalidResponse:
            return "服务器回了看不懂的内容"
        case .decoding:
            return "聊天记录没有解析成功"
        case .transport:
            return "网络没有接稳"
        case .uploadTimedOut:
            return "图片上传等得太久了，请点重试。"
        case .streamClosed:
            return "回复流中途断开"
        case let .serverMessage(message):
            return message
        }
    }
}

struct ClaudeSessionRefreshResult: Decodable, Sendable {
    let ok: Bool
    let id: Int
    let model: String
    let refreshed: Bool
}

struct ActiveChatJob: Decodable, Identifiable, Sendable {
    let id: String
    let status: String
    let clientMessageID: String?
    let userMessageID: Int?
    let assistantMessageID: Int?
    let error: String?
    let retryable: Bool?
    let nextRetryAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, error, retryable
        case clientMessageID = "client_msg_id"
        case userMessageID = "user_message_id"
        case assistantMessageID = "assistant_message_id"
        case nextRetryAt = "next_retry_at"
    }
}

enum ChatStreamEvent: Sendable {
    case receipt(userMessageID: Int?, jobID: String?, bedroom: Bool?)
    case text(String)
    case thinkingDelta(String)
    case thoughtNote(String)
    case toolRun(ChatToolRun)
    case completed(
        assistantMessageID: Int?,
        bedroom: Bool?,
        status: String?,
        error: String?,
        retryable: Bool,
        retryScheduled: Bool,
        /// 121：写完落库时服务器一并给出切好的气泡；没落库（出错、合并）时没有
        segments: [String]? = nil
    )
    case serverError(String)
}

private struct LoginResponse: Decodable {
    let ok: Bool
}

struct APNsRegistrationResponse: Decodable, Sendable {
    let ok: Bool
    let apnsConfigured: Bool

    enum CodingKeys: String, CodingKey {
        case ok
        case apnsConfigured = "apns_configured"
    }
}

struct LocationContextResponse: Decodable, Sendable {
    let ok: Bool
    let weather: String?
}

/// 121：POST /api/ke/hesitate 的回执
struct KeHesitationReceipt: Decodable, Sendable {
    let ok: Bool
    let noted: Bool?
}

struct ActiveChatSession: Decodable, Sendable {
    let id: Int
    let model: String?
}

struct ChatModelOption: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let provider: String?
    let label: String?
    let description: String?
    let group: String?
    let family: String?
    let available: Bool?

    var displayName: String {
        let value = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? id : value
    }

    var isAvailable: Bool { available ?? true }
}

struct ChatModelGroup: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let available: Bool?
    let configured: Bool?
    let message: String?
}

struct ChatModelCatalog: Decodable, Sendable {
    let models: [String]
    let `default`: String
    let options: [ChatModelOption]
    let groups: [ChatModelGroup]?
}

struct ChatModelQuotaWindow: Decodable, Hashable, Sendable {
    let kind: String
    let usedPercent: Double?
    let remainingPercent: Double?
    let windowMinutes: Int?
    let resetAt: TimeInterval?
}

struct ChatModelQuotaGroup: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let configured: Bool
    let available: Bool
    let status: String
    let usedPercent: Double?
    let remainingPercent: Double?
    let resetAt: TimeInterval?
    let stale: Bool
    let source: String
    let windows: [ChatModelQuotaWindow]
}

struct ChatModelQuotaCatalog: Decodable, Hashable, Sendable {
    let updatedAt: TimeInterval
    let selectedGroup: String?
    let currentRouteGroup: String?
    let groups: [ChatModelQuotaGroup]
}

extension ChatModelQuotaGroup {
    /// 124：几个窗口里最紧的那个还剩百分之几（这 5 小时、这一周取小的）。
    /// 先按「已用」取整再减，和话笺上「已用 58%」那行对得上；一个数都没有就 nil。
    var tightestRemainingPercent: Int? {
        func left(used: Double?, remaining: Double?) -> Int? {
            if let used { return 100 - Int(min(100, max(0, used)).rounded()) }
            if let remaining { return Int(min(100, max(0, remaining)).rounded()) }
            return nil
        }
        let perWindow = windows.compactMap { left(used: $0.usedPercent, remaining: $0.remainingPercent) }
        return perWindow.min() ?? left(used: usedPercent, remaining: remainingPercent)
    }

    /// 124：选模型那一行尾巴上的小字。用完了、要登录直接说；平时只写最紧的那个窗口还剩多少。
    var compactRemainingText: String? {
        switch status {
        case "cooldown": return "已用完"
        case "auth_required": return "要重新登录"
        case "not_configured", "unknown": return nil
        default: return tightestRemainingPercent.map { "剩 \($0)%" }
        }
    }

    /// 124：快见底了（用完或只剩一成），那行小字换成提醒色
    var isRunningLow: Bool {
        status == "cooldown" || (tightestRemainingPercent.map { $0 <= 10 } ?? false)
    }
}

struct ChatModelSection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let options: [ChatModelOption]
    let isAvailable: Bool
    let statusMessage: String?

    static let orderedIDs = ["claude_1", "claude_2", "gpt", "deepseek"]

    static func make(
        options: [ChatModelOption],
        groups: [ChatModelGroup] = []
    ) -> [ChatModelSection] {
        var metadata: [String: ChatModelGroup] = [:]
        for group in groups {
            metadata[normalizedGroup(group.id)] = group
        }
        let visibleOptions = options.filter {
            !$0.id.lowercased().contains("fable")
                && !$0.displayName.lowercased().contains("fable")
        }
        let grouped = Dictionary(grouping: visibleOptions) {
            normalizedGroup($0.family ?? $0.group ?? $0.provider ?? "")
        }
        let titles = [
            "claude_1": "Claude 1",
            "claude_2": "Claude 2",
            "gpt": "GPT",
            "deepseek": "DPSK",
        ]

        let availableIDs = orderedIDs.filter { id in
            id == "gpt" || id == "deepseek" || grouped[id] != nil || metadata[id] != nil
        }
        return availableIDs.map { id in
            let rows = grouped[id] ?? []
            let group = metadata[id]
            let available = group?.available ?? rows.contains(where: \.isAvailable)
            let message: String?
            if rows.isEmpty {
                message = group?.message ?? "尚未接入"
            } else if !available {
                message = group?.message ?? "当前不可用"
            } else {
                message = nil
            }
            let providedTitle = group?.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return ChatModelSection(
                id: id,
                title: (providedTitle?.isEmpty == false ? providedTitle : nil)
                    ?? titles[id]
                    ?? id,
                options: rows,
                isAvailable: available,
                statusMessage: message
            )
        }
    }

    static func normalizedGroup(_ rawValue: String) -> String {
        let value = rawValue.lowercased().replacingOccurrences(of: "-", with: "_")
        if value.contains("claude2") || value.contains("claude_2") { return "claude_2" }
        if value == "claude" || value.contains("claude_1")
            || value.contains("claude_subscription") { return "claude_1" }
        if value.contains("deepseek") || value == "dpsk" { return "deepseek" }
        if value.contains("codex") || value.contains("gpt") { return "gpt" }
        return "gpt"
    }
}

private struct ChatRequestBody: Encodable {
    let text: String
    let sessionID: Int
    let clientMessageID: String
    let model: String?
    let attachments: [ChatAttachment]
    /// 柯还在回时她接着发的几条，服务器可以并进最后一条一起回（旧版 App 不带这个字段，照旧排队）。
    let supportsMerge = true

    enum CodingKeys: String, CodingKey {
        case text
        case sessionID = "session_id"
        case clientMessageID = "client_msg_id"
        case model
        case attachments
        case supportsMerge = "supports_merge"
    }
}

private struct RemoteMessage: Decodable {
    let id: Int
    let author: String
    let content: String
    let createdAt: String
    let thinkSummary: String?
    let thoughtNote: String?
    let thinkSummaryRaw: String?
    let sceneMode: String?
    let attachments: [ChatAttachment]?
    let toolRuns: [ChatToolRun]?
    /// 121：柯的消息由服务器切好的气泡；她的消息没有这一项
    let segments: RemoteSegments?

    enum CodingKeys: String, CodingKey {
        case id, author, content, segments
        case createdAt = "created_at"
        case thinkSummary = "think_summary"
        case thoughtNote = "thought_note"
        case thinkSummaryRaw = "think_summary_raw"
        case sceneMode = "scene_mode"
        case attachments
        case toolRuns = "tool_runs"
    }

    func appMessage() -> Message {
        let parsedTime = ServerDateParser.parse(createdAt)
        return Message(
            id: "server-\(id)",
            serverID: id,
            sender: author == "user" ? .me : .ke,
            text: content,
            time: parsedTime.date,
            serverTimeIsValid: parsedTime.isValid,
            thoughtSummary: thinkSummary?.nilIfBlank,
            thoughtNote: thoughtNote?.nilIfBlank,
            thoughtSummaryRaw: thinkSummaryRaw?.nilIfBlank,
            sceneMode: sceneMode?.nilIfBlank,
            attachments: attachments,
            toolRuns: toolRuns,
            segments: author == "user" ? nil : segments?.values,
            isStreaming: false,
            deliveryState: .sent
        )
    }
}

/// 121：气泡切分只是锦上添花——这一项格式不对时当它没有（退回本机切法），
/// 绝不能因为它把整页聊天记录解析失败。
private struct RemoteSegments: Decodable {
    let values: [String]?

    init(from decoder: Decoder) throws {
        values = try? decoder.singleValueContainer().decode([String].self)
    }
}

private enum ServerDateParser {
    struct Result {
        let date: Date
        let isValid: Bool
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "KeApp",
        category: "ServerDateParser"
    )

    private static let formatters: [DateFormatter] = {
        ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"].map {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = $0
            return formatter
        }
    }()

    static func parse(_ raw: String) -> Result {
        if let iso = ISO8601DateFormatter().date(from: raw) {
            return Result(date: iso, isValid: true)
        }
        for formatter in formatters {
            if let value = formatter.date(from: raw) {
                return Result(date: value, isValid: true)
            }
        }
        logger.error("无法解析服务端时间戳：\(raw, privacy: .public)")
        return Result(date: .distantPast, isValid: false)
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

actor APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseURL: URL = AppConfiguration.apiBaseURL, configuration: URLSessionConfiguration = .default) {
        self.baseURL = baseURL
        HTTPCookieStorage.shared.cookieAcceptPolicy = .always
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-test-companion") {
            configuration.protocolClasses = [CompanionPreviewTransport.self]
        }
        #endif
        session = URLSession(configuration: configuration)
    }

    func login(passcode: String) async throws {
        var request = try makeRequest(path: "/api/login", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["passcode": passcode])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        do {
            let response = try decoder.decode(LoginResponse.self, from: data)
            guard response.ok else { throw APIError.unauthorized }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error)
        }
    }

    func activeSession() async throws -> ActiveChatSession {
        let request = try makeRequest(path: "/api/sessions/active")
        let (data, _) = try await perform(request)
        do {
            return try decoder.decode(ActiveChatSession.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func activeSessionID() async throws -> Int {
        try await activeSession().id
    }

    func fetchModels() async throws -> ChatModelCatalog {
        let request = try makeRequest(path: "/api/models")
        let (data, _) = try await perform(request)
        do {
            return try decoder.decode(ChatModelCatalog.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func fetchModelQuotas(sessionID: Int) async throws -> ChatModelQuotaCatalog {
        let request = try makeRequest(
            path: "/api/model-quotas",
            queryItems: [URLQueryItem(name: "session_id", value: String(sessionID))]
        )
        let (data, _) = try await perform(request)
        do {
            return try decoder.decode(ChatModelQuotaCatalog.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func usageDashboard() async throws -> UsageDashboardReport {
        let (data, _) = try await perform(try makeRequest(path: "/api/usage/dashboard"))
        do {
            return try decoder.decode(UsageDashboardReport.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func selectModel(sessionID: Int, model: String) async throws -> ActiveChatSession {
        var request = try makeRequest(path: "/api/sessions/active", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "id": sessionID,
            "model": model,
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        do {
            return try decoder.decode(ActiveChatSession.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func clearChatWindow(sessionID: Int, requestID: String) async throws -> Int {
        struct Result: Decodable { let ok: Bool; let id: Int }
        var request = try makeRequest(path: "/api/sessions/clear-window", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": sessionID, "request_id": requestID])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        let result = try decoder.decode(Result.self, from: data)
        guard result.ok, result.id > 0 else { throw APIError.invalidResponse }
        return result.id
    }

    func refreshClaudeSession(sessionID: Int, model: String) async throws -> ClaudeSessionRefreshResult {
        var request = try makeRequest(path: "/api/sessions/claude-refresh", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": sessionID, "model": model])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        let result = try decoder.decode(ClaudeSessionRefreshResult.self, from: data)
        guard result.ok, result.id == sessionID, result.model == model else {
            throw APIError.invalidResponse
        }
        return result
    }

    func fetchMessages(
        sessionID: Int,
        limit: Int = 100,
        beforeID: Int? = nil,
        aroundID: Int? = nil
    ) async throws -> [Message] {
        var queryItems = [
            URLQueryItem(name: "session_id", value: String(sessionID)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let beforeID {
            queryItems.append(URLQueryItem(name: "before_id", value: String(beforeID)))
        }
        if let aroundID {
            queryItems.append(URLQueryItem(name: "around_id", value: String(aroundID)))
        }
        let request = try makeRequest(
            path: "/api/messages",
            queryItems: queryItems
        )
        let (data, _) = try await perform(request)
        do {
            return try decoder.decode([RemoteMessage].self, from: data).map { $0.appMessage() }
        } catch {
            throw APIError.decoding(error)
        }
    }

    func deleteMessage(id: Int) async throws {
        var request = try makeRequest(path: "/api/messages/delete", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": id])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await perform(request)
    }

    func uploadAttachment(
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> ChatAttachment {
        let boundary = "KeApp-\(UUID().uuidString)"
        var request = try makeRequest(path: "/api/upload", method: "POST")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()
        body.appendMultipart("--\(boundary)\r\n")
        body.appendMultipart("Content-Disposition: form-data; name=\"original_name\"\r\n\r\n")
        body.appendMultipart("\(fileName.multipartEscaped)\r\n")
        body.appendMultipart("--\(boundary)\r\n")
        body.appendMultipart(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName.multipartEscaped)\"\r\n"
        )
        body.appendMultipart("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.appendMultipart("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (responseData, _) = try await perform(request, timeout: 60)
        do {
            return try decoder.decode(UploadResponse.self, from: responseData).attachment
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Moments stores the upload response verbatim; unlike chat, its list does not add the line prefix.
    func fetchMomentImageData(at rawURL: String) async throws -> Data {
        let path = rawURL.hasPrefix("/uploads/") ? String(rawURL.dropFirst()) : rawURL
        if path.hasPrefix("uploads/") {
            return try await fetchAttachmentData(at: baseURL.appendingPathComponent(path).absoluteString)
        }
        return try await fetchAttachmentData(at: rawURL)
    }

    /// 图片地址受与聊天接口相同的登录保护，不能交给没有明确鉴权语义的图片视图直取。
    func fetchAttachmentData(at rawURL: String) async throws -> Data {
        guard let url = URL(string: rawURL, relativeTo: baseURL)?.absoluteURL,
              url.scheme == baseURL.scheme,
              url.host == baseURL.host else {
            throw APIError.badURL
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                request.setValue(value, forHTTPHeaderField: field)
            }
        }
        let (data, _) = try await perform(request, timeout: 30)
        return data
    }

    func activeJobs(
        sessionID: Int,
        includeRecentFailures: Bool = false
    ) async throws -> [ActiveChatJob] {
        var queryItems = [URLQueryItem(name: "session_id", value: String(sessionID))]
        if includeRecentFailures {
            queryItems.append(URLQueryItem(name: "include_recent_failed", value: "1"))
        }
        let request = try makeRequest(
            path: "/api/chat/jobs",
            queryItems: queryItems
        )
        let (data, _) = try await perform(request)
        do {
            return try decoder.decode([ActiveChatJob].self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func chatJob(id: String, sessionID: Int) async throws -> ActiveChatJob {
        let request = try makeRequest(
            path: "/api/chat/jobs/\(id)",
            queryItems: [URLQueryItem(name: "session_id", value: String(sessionID))]
        )
        let (data, _) = try await perform(request)
        do {
            return try decoder.decode(ActiveChatJob.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func markSeen(sessionID: Int, throughID: Int?) async throws {
        var request = try makeRequest(path: "/api/chat/seen", method: "POST")
        var body: [String: Any] = ["session_id": sessionID]
        if let throughID { body["through_id"] = throughID }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await perform(request)
    }

    func registerAPNsToken(
        _ token: String,
        deviceName: String?
    ) async throws -> APNsRegistrationResponse {
        var request = try makeRequest(path: "/api/push/apns-token", method: "POST")
        var body: [String: String] = ["token": token]
        if let deviceName,
           !deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["device_name"] = deviceName
        }
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        do {
            return try decoder.decode(APNsRegistrationResponse.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func reportLocation(
        latitude: Double,
        longitude: Double,
        accuracy: Double?,
        place: String?
    ) async throws -> LocationContextResponse {
        var request = try makeRequest(path: "/api/context/location", method: "POST")
        var body: [String: Any] = [
            "lat": latitude,
            "lng": longitude,
        ]
        if let accuracy { body["accuracy"] = accuracy }
        if let place,
           !place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["place"] = String(place.prefix(120))
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        do {
            return try decoder.decode(LocationContextResponse.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func streamMessage(
        text: String,
        sessionID: Int,
        clientMessageID: String,
        model: String?,
        attachments: [ChatAttachment]
    ) throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        var request = try makeRequest(path: "/api/chat", method: "POST", includeCookieHeader: true)
        request.httpBody = try JSONEncoder().encode(
            ChatRequestBody(
                text: text,
                sessionID: sessionID,
                clientMessageID: clientMessageID,
                model: model,
                attachments: attachments
            )
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        return AsyncThrowingStream { continuation in
            let worker = Task {
                let eventSource = EventSource(
                    timeoutIntervalForRequest: 30,
                    timeoutIntervalForResource: 600
                )
                let dataTask = eventSource.dataTask(for: request)

                for await event in dataTask.events() {
                    if Task.isCancelled { break }
                    switch event {
                    case .open:
                        continue
                    case let .event(serverEvent):
                        guard let data = serverEvent.data else { continue }
                        do {
                            for parsed in try Self.parseStreamPayload(data) {
                                continuation.yield(parsed)
                            }
                        } catch {
                            continuation.finish(throwing: error)
                            return
                        }
                    case let .error(error):
                        if let sourceError = error as? EventSourceError {
                            switch sourceError {
                            case let .connectionError(statusCode, response):
                                if statusCode == 401 {
                                    continuation.finish(throwing: APIError.unauthorized)
                                } else {
                                    continuation.finish(throwing: APIError.badStatus(
                                        statusCode,
                                        Self.errorMessage(from: response)
                                    ))
                                }
                            default:
                                continuation.finish(throwing: APIError.transport(sourceError))
                            }
                        } else {
                            continuation.finish(throwing: APIError.transport(error))
                        }
                        return
                    case .closed:
                        continuation.finish()
                        return
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                worker.cancel()
            }
        }
    }

    func memoryUsage() async throws -> MemoryUsageReport {
        let (data, _) = try await perform(try makeRequest(path: "/api/memory/usage"))
        return try decoder.decode(MemoryUsageReport.self, from: data)
    }

    func memoryRetrieval() async throws -> MemoryRetrievalReport {
        let (data, _) = try await perform(try makeRequest(path: "/api/memory/retrieval"))
        return try decoder.decode(MemoryRetrievalReport.self, from: data)
    }

    func checkMemoryRetrieval(query: String) async throws -> MemoryRetrievalTrace {
        var request = try makeRequest(path: "/api/memory/retrieval/check", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        return try decoder.decode(MemoryRetrievalTrace.self, from: data)
    }

    func submitMemoryRetrievalFeedback(traceID: String, kind: MemoryFeedbackKind,
                                       candidateID: String?, note: String) async throws -> MemoryFeedbackReceipt {
        var request = try makeRequest(path: "/api/memory/retrieval/feedback", method: "POST")
        var body: [String: Any] = ["trace_id": traceID, "kind": kind.rawValue, "note": note]
        if let candidateID { body["candidate_id"] = candidateID }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        return try decoder.decode(MemoryFeedbackReceipt.self, from: data)
    }

    func appQuotes() async throws -> AppQuotePage {
        let (data, _) = try await perform(try makeRequest(path: "/api/memory/app-quotes"))
        return try decoder.decode(AppQuotePage.self, from: data)
    }

    func memoryGarden() async throws -> MemoryGardenPage {
        try await readResource("/api/memory/garden")
    }

    func changeMemoryFlower(id: String, action: String, note: String?, loved: Bool?) async throws {
        guard ["wither", "revive", "love"].contains(action),
              !id.isEmpty, !id.contains("/"), id != ".", id != ".." else {
            throw APIError.invalidResponse
        }
        // makeRequest's URL path builder performs escaping once. Pre-escaping double-encodes IDs.
        var request = try makeRequest(path: "/api/memory/garden/\(id)/\(action)", method: "POST")
        var body: [String: Any] = [:]
        if let note { body["note"] = note }
        if let loved { body["loved"] = loved }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await perform(request)
    }

    func saveAppQuote(messageID: Int, note: String) async throws {
        var request = try makeRequest(path: "/api/memory/app-quotes", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["message_id": messageID, "note": note])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await perform(request)
    }

    func removeAppQuote(id: Int) async throws {
        _ = try await perform(try makeRequest(path: "/api/memory/app-quotes/\(id)", method: "DELETE"))
    }

    func reviewPending(offset: Int = 0) async throws -> ReviewPage {
        let request = try makeRequest(path: "/api/memory/pending", queryItems: [URLQueryItem(name: "offset", value: String(offset))])
        let (data, _) = try await perform(request)
        return try decoder.decode(ReviewPage.self, from: data)
    }

    func submitReview(_ operation: ReviewOperation) async throws -> ReviewReceipt {
        var request = try makeRequest(path: "/api/memory/review", method: "POST")
        request.httpBody = try JSONEncoder().encode(operation)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        return try decoder.decode(ReviewReceipt.self, from: data)
    }

    func reviewStats() async throws -> ReviewStats {
        let (data, _) = try await perform(try makeRequest(path: "/api/memory/stats"))
        return try decoder.decode(ReviewStats.self, from: data)
    }

    func reviewedFacts(offset: Int = 0) async throws -> ReviewedFactsPage {
        let request = try makeRequest(path: "/api/memory/facts", queryItems: [URLQueryItem(name: "offset", value: String(offset))])
        let (data, _) = try await perform(request)
        return try decoder.decode(ReviewedFactsPage.self, from: data)
    }

    func fetchStickyNotes() async throws -> [StickyNote] {
        try await readResource("/api/sticky-notes")
    }
    func setStickyNoteAcknowledged(id: String, acknowledged: Bool) async throws {
        try await writeResource(acknowledged ? "/api/sticky-notes/ack" : "/api/sticky-notes/unack", body: ["id": id])
    }
    func saveStickyNote(id: String, content: String) async throws -> StickyNote {
        var request = try makeRequest(path: "/api/sticky-notes", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": id, "content": content])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        return try decoder.decode(StickyNote.self, from: data)
    }
    func deleteStickyNote(id: String) async throws {
        try await writeResource("/api/sticky-notes/delete", body: ["id": id])
    }

    func fetchDrawer() async throws -> RemoteDrawer { try await readResource("/api/drawer") }

    func fetchHut() async throws -> RemoteHut { try await readResource("/api/hut") }
    func sendHutLetter(text: String) async throws { try await writeResource("/api/hut/letter", body: ["text": text]) }

    func fetchAnniversaries() async throws -> [RemoteAnniversary] {
        try await readResource("/api/anniversaries")
    }

    func fetchSchedule() async throws -> RemoteSchedule {
        try await readResource("/api/schedule")
    }

    func fetchShifts() async throws -> [RemoteShift] {
        try await readResource("/api/shifts")
    }

    func fetchPeriods() async throws -> [RemotePeriod] {
        try await readResource("/api/periods")
    }

    func fetchDiaries(query: String = "", offset: Int = 0, limit: Int = 50) async throws -> [RemoteDiary] {
        let request = try makeRequest(path: "/api/diary", queryItems: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        let (data, _) = try await perform(request)
        return try decoder.decode([RemoteDiary].self, from: data)
    }

    // MARK: 123 夜里（日记页的第二栏；只在那里出现，聊天和「柯的」卡片都不拉）

    /// GET /api/night?limit=&before_id= → {"entries": [...]}，新的在上面；before_id 往前翻
    func fetchNight(limit: Int = 100, beforeID: Int? = nil) async throws -> [RemoteNight] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let beforeID { items.append(URLQueryItem(name: "before_id", value: String(beforeID))) }
        let (data, _) = try await perform(try makeRequest(path: "/api/night", queryItems: items))
        do { return try decoder.decode(NightPage.self, from: data).entries }
        catch { throw APIError.decoding(error) }
    }

    /// POST /api/night/<id>/comment：评价和那句话每次一起发（"" 就是清掉），回改好的那一篇；找不到是 404
    func commentNight(id: Int, rating: NightRating?, comment: String) async throws -> RemoteNight {
        let reply: NightCommentReply = try await postNotebook("/api/night/\(id)/comment",
                                                              body: NightComment.body(rating: rating, comment: comment))
        guard let entry = reply.entry else { throw APIError.serverMessage(reply.error ?? "") }
        return entry
    }

    func fetchArchivedMessages(query: String = "", beforeID: Int? = nil, limit: Int = 50) async throws -> [ArchivedChatMessage] {
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let beforeID {
            queryItems.append(URLQueryItem(name: "before_id", value: String(beforeID)))
        }
        let request = try makeRequest(path: "/api/history/archive", queryItems: queryItems)
        let (data, _) = try await perform(request)
        return try decoder.decode([ArchivedChatMessage].self, from: data)
    }

    func fetchMoments() async throws -> [RemoteMoment] {
        try await readResource("/api/moments")
    }

    func fetchMomentsActivity() async throws -> MomentsActivity {
        try await readResource("/api/moments/status")
    }

    func shuffleTarot(question: String, spread: String) async throws -> TarotDeal {
        var request = try makeRequest(path: "/api/tarot/shuffle", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["question": question, "spread": spread])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        let deal: TarotDeal
        do { deal = try decoder.decode(TarotDeal.self, from: data) }
        catch { throw APIError.serverMessage("牌阵信息没有收完整，请重新洗牌。") }
        guard deal.isValid, deal.spread == spread else { throw APIError.serverMessage("牌阵没有准备好，请重新洗牌。") }
        return deal
    }

    func pickTarot(deal: TarotDeal, picks: [Int]) async throws -> TarotCast {
        guard picks.count == deal.positions.count, Set(picks).count == picks.count,
              picks.allSatisfy({ (0..<deal.deck_size).contains($0) }) else {
            throw APIError.serverMessage("选牌数量或序号不对，请重新选牌。")
        }
        var request = try makeRequest(path: "/api/tarot/pick", method: "POST")
        request.httpBody = try JSONEncoder().encode(TarotPickRequest(deal_id: deal.deal_id, picks: picks))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        let cast: TarotCast
        do { cast = try decoder.decode(TarotCast.self, from: data) }
        catch { throw APIError.serverMessage("牌面信息没有收完整，请重试翻牌。") }
        guard cast.cards.count == deal.positions.count, cast.spread == deal.spread,
              cast.cards.map(\.position) == deal.positions else {
            throw APIError.serverMessage("牌面没有收完整，请重试翻牌。")
        }
        return cast
    }

    /// 塔罗：服务器抽牌落账，返回牌面；柯只断不抽。
    func drawTarot(question: String, spread: String) async throws -> TarotCast {
        var request = try makeRequest(path: "/api/tarot/draw", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["question": question, "spread": spread])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        do { return try decoder.decode(TarotCast.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    /// 算命：服务器排盘落账，返回摘要和盘面；柯只说不算。
    func runFortune(kind: String, inputs: [String: Any]) async throws -> FortuneResult {
        var request = try makeRequest(path: "/api/fortune/run", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["kind": kind, "inputs": inputs])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        do { return try decoder.decode(FortuneResult.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    /// 共读网页边注：只发送当前可见片段，服务器不保存网址或正文。
    func annotateWebReading(title: String, url: String, excerpt: String) async throws -> WebReadingComment {
        var request = try makeRequest(path: "/api/reading/web-annotate", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "title": title,
            "url": url,
            "excerpt": excerpt,
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        do { return try decoder.decode(WebReadingComment.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    /// 抽屉：柯手边在跑什么活，让她自己看见，不用只听他说。
    func fetchWorkDrawer() async throws -> WorkDrawer { try await readResource("/api/work/drawer") }

    func addAnniversary(name: String, date: String, emoji: String = "💞") async throws {
        try await writeResource("/api/anniversaries", body: ["name": name, "date": date, "emoji": emoji])
    }

    func deleteAnniversary(id: Int) async throws {
        try await writeResource("/api/anniversaries/delete", body: ["id": id])
    }

    func setShift(date: String, shift: String, note: String) async throws {
        try await writeResource("/api/shifts", body: ["date": date, "shift": shift, "note": note])
    }

    func deleteShift(date: String) async throws {
        try await writeResource("/api/shifts/delete", body: ["date": date])
    }

    func addPeriod(startDate: String, note: String) async throws {
        try await writeResource("/api/periods", body: ["start_date": startDate, "note": note])
    }

    // Requires the explicit end-date operation documented in the Build 73 handoff.
    // A 404/400 leaves the local end date pending; it never removes the start record.
    func endPeriod(id: Int, endDate: String) async throws {
        try await writeResource("/api/periods/end", body: ["id": id, "end_date": endDate])
    }

    func deletePeriod(id: Int) async throws {
        try await writeResource("/api/periods/delete", body: ["id": id])
    }

    func addDiary(title: String, content: String, mood: String) async throws {
        try await writeResource("/api/diary/entry", body: ["title": title, "content": content, "mood": mood, "author": "佳佳"])
    }

    func addDiaryComment(id: Int, content: String) async throws {
        try await writeResource("/api/diary/comment", body: ["id": id, "content": content, "author": "佳佳"])
    }

    func fetchDiaryComments(id: Int) async throws -> [RemoteMomentComment] {
        let request = try makeRequest(path: "/api/diary/comments", queryItems: [URLQueryItem(name: "id", value: String(id))])
        let (data, _) = try await perform(request)
        return try decoder.decode([RemoteMomentComment].self, from: data)
    }

    func deleteDiary(id: Int) async throws {
        try await writeResource("/api/diary/delete", body: ["id": id])
    }

    func addMoment(content: String, image: String = "") async throws {
        try await writeResource("/api/moments", body: ["content": content, "image": image, "visibility": "private"])
    }

    func setMomentLike(id: Int, liked: Bool) async throws {
        try await writeResource("/api/moments/like", body: ["id": id, "liked": liked])
    }

    func addMomentComment(id: Int, content: String) async throws {
        try await writeResource("/api/moments/comment", body: ["moment_id": id, "content": content])
    }

    func editMoment(id: Int, content: String) async throws {
        try await writeResource("/api/moments/edit", body: ["id": id, "content": content])
    }

    func deleteMoment(id: Int) async throws {
        try await writeResource("/api/moments/delete", body: ["id": id])
    }

    func editMomentComment(id: Int, content: String) async throws {
        try await writeResource("/api/moments/comment/edit", body: ["id": id, "content": content])
    }

    func deleteMomentComment(id: Int) async throws {
        try await writeResource("/api/moments/comment/delete", body: ["id": id])
    }

    func fetchPrivateRecords(date: String) async throws -> [RemotePrivateRecord] {
        let request = try makeRequest(path: "/api/companion/records", queryItems: [
            URLQueryItem(name: "start", value: date), URLQueryItem(name: "end", value: date)])
        let (data, _) = try await perform(request)
        do { return try decoder.decode([RemotePrivateRecord].self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    func fetchIntimateCounts(start: String, end: String) async throws -> [RemoteIntimateCount] {
        let request = try makeRequest(path: "/api/companion/intimate-counts", queryItems: [
            URLQueryItem(name: "start", value: start), URLQueryItem(name: "end", value: end)])
        let (data, _) = try await perform(request)
        do { return try decoder.decode([RemoteIntimateCount].self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    func savePrivateRecord(date: String, note: String, operationID: String) async throws {
        try await writeResource("/api/companion/records", body: ["kind": "intimate", "action": "create", "date": date, "note": note, "operation_id": operationID])
    }

    func deletePrivateRecord(id: Int, operationID: String) async throws {
        try await writeResource("/api/companion/records", body: ["kind": "intimate", "action": "delete", "id": id, "operation_id": operationID])
    }

    func editAnniversary(id: Int, name: String, date: String, operationID: String) async throws {
        try await writeResource("/api/companion/records", body: ["kind": "anniversary", "action": "update", "id": id, "date": date, "note": name, "operation_id": operationID])
    }

    // MARK: 我们的小本子（荷包、食单、药盒；2026-10-14）。她记的都标 me，柯在聊天里记的标 ke。

    func fetchNotebook() async throws -> NotebookSnapshot { try await readResource("/api/notebook") }

    @discardableResult func createNotebookItem(kind: String, fields: [String: Any]) async throws -> NotebookItem {
        var body = fields; body["kind"] = kind
        return try await postNotebook("/api/notebook/items", body: body)
    }

    @discardableResult func updateNotebookItem(id: Int, fields: [String: Any]) async throws -> NotebookItem {
        try await postNotebook("/api/notebook/items/\(id)", body: fields)
    }

    func deleteNotebookItem(id: Int) async throws {
        try await writeResource("/api/notebook/items/\(id)/delete", body: [:])
    }

    func setNotebookDose(when: String, taken: Bool) async throws {
        try await writeResource("/api/notebook/dose", body: ["when": when, "taken": taken])
    }

    func setNotebookCap(yuan: Double) async throws {
        try await writeResource("/api/notebook/settings", body: ["cap": yuan])
    }

    // MARK: 121 攒钱罐（荷包里的「攒钱」页）。回来的金额都是分；发出去的 amount / target 是元，可以带小数。
    // 不对的时候服务器回 400/404 {"error": "中文原因"}，perform 里会变成 APIError.badStatus，原话照给她看。
    // 原来荷包里那条「一起存」（/api/notebook/save）挪到这里了，旧的那个入口不再用。

    func fetchJars() async throws -> JarOverview { try await readResource("/api/notebook/jars") }

    func fetchJar(id: Int) async throws -> JarDetail { try await readResource("/api/notebook/jars/\(id)") }

    /// deadline 是 "YYYY-MM-DD"，不定日期传 ""
    func createJar(title: String, target: Double, deadline: String) async throws -> JarReply {
        try await postNotebook("/api/notebook/jars", body: ["title": title, "target": Self.yuanValue(target), "deadline": deadline])
    }

    /// 改名字 / 目标（元）/ 日期（"" 是不定日期）
    func updateJar(id: Int, title: String, target: Double, deadline: String) async throws -> JarReply {
        try await postNotebook("/api/notebook/jars/\(id)", body: ["title": title, "target": Self.yuanValue(target), "deadline": deadline])
    }

    /// undo: true 是把刚删掉的罐子放回来
    func deleteJar(id: Int, undo: Bool = false) async throws -> JarReply {
        let body: [String: Any] = undo ? ["undo": true] : [:]
        return try await postNotebook("/api/notebook/jars/\(id)/delete", body: body)
    }

    /// 存一笔 / 取出来：amount 总是正数，take 决定方向；operation_id 让重试不会存成两笔
    func addJarEntry(jarID: Int, amount: Double, take: Bool, note: String, operationID: String) async throws -> JarReply {
        try await postNotebook("/api/notebook/jars/\(jarID)/entries",
                               body: ["amount": Self.yuanValue(amount), "take": take, "note": note, "operation_id": operationID])
    }

    /// 改一笔：amount（元，正数）/ take（是不是取出来）/ note
    func updateJarEntry(id: Int, amount: Double, take: Bool, note: String) async throws -> JarReply {
        try await postNotebook("/api/notebook/jar-entries/\(id)", body: ["amount": Self.yuanValue(amount), "take": take, "note": note])
    }

    func deleteJarEntry(id: Int, undo: Bool = false) async throws -> JarReply {
        let body: [String: Any] = undo ? ["undo": true] : [:]
        return try await postNotebook("/api/notebook/jar-entries/\(id)/delete", body: body)
    }

    /// 上个月省下的钱：放进哪个罐子（jar_id 不传就是服务器默认的随手攒），或者这次不放
    func answerJarMonthTip(accept: Bool, jarID: Int?) async throws -> JarReply {
        var body: [String: Any] = ["accept": accept]
        if let jarID { body["jar_id"] = jarID }
        return try await postNotebook("/api/notebook/jars/month-tip", body: body)
    }

    /// 元按两位小数原样发出去：12.3 就是 12.3，不会被写成 12.300000000000001
    static func yuanValue(_ yuan: Double) -> NSDecimalNumber {
        NSDecimalNumber(string: String(format: "%.2f", yuan))
    }

    // MARK: 柯的长窗（来信设置、洗澡、换窗、钉住；2026-10-16）

    func fetchKeSettings() async throws -> KeProactiveSettings { try await readResource("/api/ke/settings") }

    /// 只传改动的那几项；后端回完整设置，不合法时回 400 {"error": "..."}。
    func updateKeSettings(_ patch: [String: Any]) async throws -> KeProactiveSettings {
        try await postNotebook("/api/ke/settings", body: patch)
    }

    func fetchKeWindow() async throws -> KeWindowState { try await readResource("/api/ke/window") }

    /// 202 + job；柯正在忙别的时回 409。
    func washKeWindow() async throws -> KeWindowJob? {
        let response: KeJobResponse = try await postNotebook("/api/ke/window/wash", body: [:])
        return response.job
    }

    func rotateKeWindow(picks: [Int]) async throws -> KeWindowJob? {
        let response: KeJobResponse = try await postNotebook("/api/ke/window/rotate", body: ["picks": picks])
        return response.job
    }

    /// 钉住按整轮算：传这一轮里任意一条消息的 id 都行。
    func setKePin(messageID: Int, pinned: Bool) async throws {
        var request = try makeRequest(path: "/api/ke/pins", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["message_id": messageID, "pinned": pinned])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? String, !error.isEmpty {
            throw APIError.serverMessage(error)
        }
    }

    func fetchKeRounds(limit: Int = 30, beforeID: Int? = nil) async throws -> KeRoundPage {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let beforeID { items.append(URLQueryItem(name: "before_id", value: String(beforeID))) }
        let (data, _) = try await perform(try makeRequest(path: "/api/ke/rounds", queryItems: items))
        do { return try decoder.decode(KeRoundPage.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    // MARK: 121 输入框的动静：只报字数和删光/卡住/切走，绝不带她写的字

    /// 她在打字：只带现在框里几个字。回 {"ok": true}。
    func reportComposerTyping(length: Int) async throws {
        try await writeResource("/api/ke/typing", body: ["len": length])
    }

    /// kind 是 cleared / stuck / left；服务器不看 peak < 4，40 秒后自己决定要不要叫醒柯。
    /// 回 {"ok": true, "noted": Bool}，noted 表示这次记下了。
    @discardableResult
    func reportComposerHesitation(kind: String, peak: Int) async throws -> Bool {
        let receipt: KeHesitationReceipt = try await postNotebook("/api/ke/hesitate", body: ["kind": kind, "peak": peak])
        return receipt.noted ?? false
    }

    private func postNotebook<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var request = try makeRequest(path: path, method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    private func readResource<T: Decodable>(_ path: String) async throws -> T {
        let (data, _) = try await perform(try makeRequest(path: path))
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    private func writeResource(_ path: String, body: [String: Any]) async throws {
        var request = try makeRequest(path: path, method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        if let error = result["error"] as? String { throw APIError.serverMessage(error) }
        guard result["ok"] as? Bool == true || result["id"] as? Int != nil else {
            throw APIError.invalidResponse
        }
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        includeCookieHeader: Bool = false
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.badURL
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let cookies = HTTPCookieStorage.shared.cookies(for: url),
           !cookies.isEmpty {
            for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                request.setValue(value, forHTTPHeaderField: field)
            }
        }
        return request
    }

    private func perform(
        _ request: URLRequest,
        timeout: TimeInterval? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let payload: (Data, URLResponse)
            if let timeout {
                payload = try await withThrowingTaskGroup(
                    of: (Data, URLResponse).self
                ) { group in
                    defer { group.cancelAll() }
                    group.addTask { [session] in
                        try await session.data(for: request)
                    }
                    group.addTask {
                        try await Task.sleep(
                            nanoseconds: UInt64(timeout * 1_000_000_000)
                        )
                        throw APIError.uploadTimedOut
                    }
                    guard let first = try await group.next() else {
                        throw APIError.invalidResponse
                    }
                    return first
                }
            } else {
                payload = try await session.data(for: request)
            }
            let (data, response) = payload
            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            if http.statusCode == 401 { throw APIError.unauthorized }
            guard 200...299 ~= http.statusCode else {
                let message = Self.errorMessage(from: data)
                throw APIError.badStatus(http.statusCode, message)
            }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }

    static func parseStreamPayload(_ data: String) throws -> [ChatStreamEvent] {
        guard let raw = data.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        var events: [ChatStreamEvent] = []
        let bedroom = object["bedroom"] as? Bool
        let userMessageID = number(object["user_message_id"])
        let jobID = object["job_id"] as? String
        if userMessageID != nil || jobID != nil {
            events.append(.receipt(
                userMessageID: userMessageID,
                jobID: jobID,
                bedroom: bedroom
            ))
        }
        if let value = object["thinking_summary_delta"] as? String, !value.isEmpty {
            events.append(.thinkingDelta(value))
        }
        if let value = object["think_summary"] as? String, !value.isEmpty {
            events.append(.thoughtNote(value))
        }
        if let value = object["tool_run"] as? [String: Any],
           let encoded = try? JSONSerialization.data(withJSONObject: value),
           let toolRun = try? JSONDecoder().decode(ChatToolRun.self, from: encoded) {
            events.append(.toolRun(toolRun))
        }
        if let value = object["t"] as? String, !value.isEmpty {
            events.append(.text(value))
        }
        if let value = object["error"] as? String, !value.isEmpty {
            events.append(.serverError(value))
        }
        if object["done"] as? Bool == true {
            events.append(.completed(
                assistantMessageID: number(object["assistant_message_id"]),
                bedroom: bedroom,
                status: object["status"] as? String,
                error: object["error"] as? String,
                retryable: object["retryable"] as? Bool ?? false,
                retryScheduled: object["retry_scheduled"] as? Bool ?? false,
                segments: (object["segments"] as? [Any])?.compactMap { $0 as? String }
            ))
        }
        return events
    }

    private static func number(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["error"] as? String else {
            return ""
        }
        return message
    }
}

struct UploadResponse: Decodable {
    let url: String
    let name: String
    let kind: String?

    var attachment: ChatAttachment {
        // 后端契约只保证 url + name；老响应没有 kind 时交给扩展名识别。
        ChatAttachment(url: url, name: name, kind: kind ?? "")
    }
}

private extension Data {
    mutating func appendMultipart(_ value: String) {
        append(Data(value.utf8))
    }
}

private extension String {
    var multipartEscaped: String {
        replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
    }
}

extension APIClient: MemoryReviewService {}
extension APIClient: NightDiaryService {}
