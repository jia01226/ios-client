import Foundation
import EventSource

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
    case thoughtSummary(String)
    case completed(assistantMessageID: Int?, bedroom: Bool?)
    case serverError(String)
}

private struct LoginResponse: Decodable {
    let ok: Bool
}

private struct ActiveSessionResponse: Decodable {
    let id: Int
}

private struct ChatRequestBody: Encodable {
    let text: String
    let sessionID: Int
    let clientMessageID: String

    enum CodingKeys: String, CodingKey {
        case text
        case sessionID = "session_id"
        case clientMessageID = "client_msg_id"
    }
}

private struct RemoteMessage: Decodable {
    let id: Int
    let author: String
    let content: String
    let createdAt: String
    let thoughtNote: String?

    enum CodingKeys: String, CodingKey {
        case id, author, content
        case createdAt = "created_at"
        case thoughtNote = "thought_note"
    }

    func appMessage() -> Message {
        Message(
            id: "server-\(id)",
            serverID: id,
            sender: author == "user" ? .me : .ke,
            text: content,
            time: ServerDateParser.parse(createdAt),
            thoughtSummary: thoughtNote?.nilIfBlank,
            isStreaming: false,
            deliveryState: .sent
        )
    }
}

private enum ServerDateParser {
    private static let formatters: [DateFormatter] = {
        ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"].map {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = $0
            return formatter
        }
    }()

    static func parse(_ raw: String) -> Date {
        if let iso = ISO8601DateFormatter().date(from: raw) { return iso }
        for formatter in formatters {
            if let value = formatter.date(from: raw) { return value }
        }
        return .now
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

    func activeSessionID() async throws -> Int {
        let request = try makeRequest(path: "/api/sessions/active")
        let (data, _) = try await perform(request)
        do {
            return try decoder.decode(ActiveSessionResponse.self, from: data).id
        } catch {
            throw APIError.decoding(error)
        }
    }

    func fetchMessages(sessionID: Int, limit: Int = 100) async throws -> [Message] {
        let request = try makeRequest(
            path: "/api/messages",
            queryItems: [
                URLQueryItem(name: "session_id", value: String(sessionID)),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        let (data, _) = try await perform(request)
        do {
            return try decoder.decode([RemoteMessage].self, from: data).map { $0.appMessage() }
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
        clientMessageID: String
    ) throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        var request = try makeRequest(path: "/api/chat", method: "POST", includeCookieHeader: true)
        request.httpBody = try JSONEncoder().encode(
            ChatRequestBody(
                text: text,
                sessionID: sessionID,
                clientMessageID: clientMessageID
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
            events.append(.thoughtSummary(value))
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
