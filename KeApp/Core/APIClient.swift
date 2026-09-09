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
        retryScheduled: Bool
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
        let grouped = Dictionary(grouping: options) {
            normalizedGroup($0.family ?? $0.group ?? $0.provider ?? "")
        }
        let titles = [
            "claude_1": "Claude 1",
            "claude_2": "Claude 2",
            "gpt": "GPT",
            "deepseek": "DPSK",
        ]

        return orderedIDs.map { id in
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

    enum CodingKeys: String, CodingKey {
        case text
        case sessionID = "session_id"
        case clientMessageID = "client_msg_id"
        case model
        case attachments
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

    enum CodingKeys: String, CodingKey {
        case id, author, content
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
            isStreaming: false,
            deliveryState: .sent
        )
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

    func appQuotes() async throws -> AppQuotePage {
        let (data, _) = try await perform(try makeRequest(path: "/api/memory/app-quotes"))
        return try decoder.decode(AppQuotePage.self, from: data)
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

    func fetchDrawer() async throws -> RemoteDrawer { try await readResource("/api/drawer") }

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

    func fetchDiaries() async throws -> [RemoteDiary] {
        try await readResource("/api/diary")
    }

    func fetchMoments() async throws -> [RemoteMoment] {
        try await readResource("/api/moments")
    }

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

    func fetchPrivateRecords(date: String) async throws -> [RemotePrivateRecord] {
        let request = try makeRequest(path: "/api/companion/records", queryItems: [
            URLQueryItem(name: "start", value: date), URLQueryItem(name: "end", value: date)])
        let (data, _) = try await perform(request)
        do { return try decoder.decode([RemotePrivateRecord].self, from: data) }
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
        if includeCookieHeader,
           let cookies = HTTPCookieStorage.shared.cookies(for: url),
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
                retryScheduled: object["retry_scheduled"] as? Bool ?? false
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
