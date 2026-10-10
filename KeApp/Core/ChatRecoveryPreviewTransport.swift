#if DEBUG
import Foundation
import SwiftUI

/// Simulates a server that finishes while the UI process is suspended. The stream
/// deliberately never delivers completion; only the real recovery path can reveal it.
actor ChatRecoveryPreviewTransport: ChatReplyTransport {
    private var clientID = ""
    private var sentAt: Date?
    private var continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation?
    private var finished: Bool { sentAt.map { Date().timeIntervalSince($0) >= 2 } ?? false }
    func activeSession() async throws -> ActiveChatSession { ActiveChatSession(id: 982, model: nil) }
    func streamMessage(text: String, sessionID: Int, clientMessageID: String, model: String?, attachments: [ChatAttachment]) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        clientID = clientMessageID; sentAt = Date()
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
            continuation.yield(.receipt(userMessageID: 98201, jobID: "foreground-fixture", bedroom: nil))
            continuation.yield(.text("正在写这一句…"))
        }
    }
    func activeJobs(sessionID: Int, includeRecentFailures: Bool) async throws -> [ActiveChatJob] { [] }
    func chatJob(id: String, sessionID: Int) async throws -> ActiveChatJob {
        ActiveChatJob(id: id, status: finished ? "done" : "running", clientMessageID: clientID,
                      userMessageID: 98201, assistantMessageID: finished ? 98202 : nil,
                      error: nil, retryable: false, nextRetryAt: nil)
    }
    func fetchMessages(sessionID: Int, limit: Int, beforeID: Int?, aroundID: Int?) async throws -> [Message] {
        guard let sentAt else { return [] }
        var values = [Message(id: "server-98201", serverID: 98201, sender: .me, text: "切回来看看", time: sentAt)]
        if finished { values.append(Message(id: "server-98202", serverID: 98202, sender: .ke,
                                            text: "我已经回好了，你回来就能看见。", time: sentAt.addingTimeInterval(2))) }
        return values
    }
    func markSeen(sessionID: Int, throughID: Int?) async throws {}
}
/// Measures foreground entry → appearance of the completed reply inside the app,
/// avoiding XCTest's cross-process accessibility lookup/idle wait overhead.
@MainActor
final class ChatRecoveryUITestTiming: ObservableObject {
    static let shared = ChatRecoveryUITestTiming()
    private var began: TimeInterval?
    @Published private(set) var elapsed: TimeInterval?
    func begin() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-test-foreground-recovery") else { return }
        began = ProcessInfo.processInfo.systemUptime
        elapsed = nil
    }
    func appeared(_ message: Message) {
        guard message.serverID == 98202, let began, elapsed == nil else { return }
        elapsed = ProcessInfo.processInfo.systemUptime - began
    }
}

struct ChatRecoveryUITestTimingProbe: View {
    @ObservedObject private var timing = ChatRecoveryUITestTiming.shared
    var body: some View {
        if let elapsed = timing.elapsed {
            Text(String(format: "%.4f", elapsed))
                .font(.system(size: 1))
                .accessibilityIdentifier("foreground-recovery-seconds")
                .allowsHitTesting(false)
        }
    }
}
#endif
