#if DEBUG
import Foundation

/// Local UI verification of the real view-model send/receipt/completion path.
/// This transport never contacts Ke or the live chat endpoints.
actor TarotHandoffPreviewTransport: ChatReplyTransport {
    private var history: [Message] = []
    func activeSession() async throws -> ActiveChatSession { ActiveChatSession(id: 1, model: nil) }
    func activeJobs(sessionID: Int, includeRecentFailures: Bool) async throws -> [ActiveChatJob] { [] }
    func chatJob(id: String, sessionID: Int) async throws -> ActiveChatJob { throw APIError.invalidResponse }
    func fetchMessages(sessionID: Int, limit: Int, beforeID: Int?, aroundID: Int?) async throws -> [Message] { history }
    func markSeen(sessionID: Int, throughID: Int?) async throws {}
    func streamMessage(text: String, sessionID: Int, clientMessageID: String, model: String?, attachments: [ChatAttachment]) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        guard text.contains("[塔罗#7]"), attachments.isEmpty else { throw APIError.invalidResponse }
        let userID = 93000 + history.count
        let reply = "牌面核对：月亮（逆位），圣杯二、太阳（正位）。已收到你写的问题。"
        history.append(Message(id: "server-\(userID)", serverID: userID, clientID: clientMessageID, sender: .me, text: text, time: .now))
        history.append(Message(id: "server-\(userID + 1)", serverID: userID + 1, sender: .ke, text: reply, time: .now))
        return AsyncThrowingStream { continuation in
            continuation.yield(.receipt(userMessageID: userID, jobID: nil, bedroom: nil))
            continuation.yield(.text(reply))
            continuation.yield(.completed(assistantMessageID: userID + 1, bedroom: nil, status: "done", error: nil, retryable: false, retryScheduled: false))
            continuation.finish()
        }
    }
}
#endif
