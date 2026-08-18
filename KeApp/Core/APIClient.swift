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
        case .streamClosed:
            return "回复流中途断开"
        case let .serverMessage(message):
            return message
        }
    }
}

struct ActiveChatJob: Decodable, Identifiable, Sendable {
    let id: String
    let status: String
}

enum ChatStreamEvent: Sendable {
    case receipt(userMessageID: Int?, jobID: String?, bedroom: Bool?)
    case text(String)
    case thinkingDelta(String)
    case thoughtNote(String)
    case completed(assistantMessageID: Int?, bedroom: Bool?)
    case serverError(String)
}

private struct LoginResponse: Decodable {
    let ok: Bool
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

    var displayName: String {
        let value = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? id : value
    }
}

struct ChatModelCatalog: Decodable, Sendable {
    let models: [String]
    let `default`: String
    let options: [ChatModelOption]
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
    let attachments: [ChatAttachment]?

    enum CodingKeys: String, CodingKey {
        case id, author, content
        case createdAt = "created_at"
        case thinkSummary = "think_summary"
        case thoughtNote = "thought_note"
        case attachments
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
            attachments: attachments,
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

    private let baseURL = AppConfiguration.apiBaseURL
    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        HTTPCookieStorage.shared.cookieAcceptPolicy = .always
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
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

        let (responseData, _) = try await perform(request)
        do {
            return try decoder.decode(UploadResponse.self, from: responseData).attachment
        } catch {
            throw APIError.decoding(error)
        }
    }

    func activeJobs(sessionID: Int) async throws -> [ActiveChatJob] {
        let request = try makeRequest(
            path: "/api/chat/jobs",
            queryItems: [URLQueryItem(name: "session_id", value: String(sessionID))]
        )
        let (data, _) = try await perform(request)
        do {
            return try decoder.decode([ActiveChatJob].self, from: data)
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

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
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

    private static func parseStreamPayload(_ data: String) throws -> [ChatStreamEvent] {
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
        if let value = object["t"] as? String, !value.isEmpty {
            events.append(.text(value))
        }
        if let value = object["error"] as? String, !value.isEmpty {
            events.append(.serverError(value))
        }
        if object["done"] as? Bool == true {
            events.append(.completed(
                assistantMessageID: number(object["assistant_message_id"]),
                bedroom: bedroom
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

private struct UploadResponse: Decodable {
    let url: String
    let name: String
    let kind: String

    var attachment: ChatAttachment {
        ChatAttachment(url: url, name: name, kind: kind)
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
