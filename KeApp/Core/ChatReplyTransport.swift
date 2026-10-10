import Foundation

/// The existing reply endpoints, injectable so lifecycle races can be reproduced without a server.
protocol ChatReplyTransport: Sendable {
    func activeSession() async throws -> ActiveChatSession
    func streamMessage(text: String, sessionID: Int, clientMessageID: String, model: String?, attachments: [ChatAttachment]) async throws -> AsyncThrowingStream<ChatStreamEvent, Error>
    func activeJobs(sessionID: Int, includeRecentFailures: Bool) async throws -> [ActiveChatJob]
    func chatJob(id: String, sessionID: Int) async throws -> ActiveChatJob
    func fetchMessages(sessionID: Int, limit: Int, beforeID: Int?, aroundID: Int?) async throws -> [Message]
    func markSeen(sessionID: Int, throughID: Int?) async throws
}

extension APIClient: ChatReplyTransport {}
