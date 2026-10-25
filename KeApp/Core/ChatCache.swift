import Foundation

/// 聊天记录在 VPS 才是正式数据；这里仅保存最近一页，供断网或冷启动先显示。
/// 缓存目录明确排除 iCloud 备份，避免私人对话跟随设备备份进入云端。
actor ChatCache {
    static let shared = ChatCache()

    struct Snapshot: Sendable {
        let sessionID: Int
        let messages: [Message]
    }

    private struct Envelope: Codable {
        let sessionID: Int
        let savedAt: Date
        let messages: [Message]
    }

    private let fileURL: URL?

    init(fileName: String = "messages.json") {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fileURL = nil
            return
        }

        let directory = applicationSupport.appendingPathComponent(
            "KeChatCache",
            isDirectory: true
        )

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectory = directory
            try mutableDirectory.setResourceValues(values)
            fileURL = directory.appendingPathComponent(fileName)
        } catch {
            fileURL = nil
        }
    }

    func load(sessionID: Int) -> [Message] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.sessionID == sessionID else {
            return []
        }
        return envelope.messages
    }

    func loadLatest() -> Snapshot? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return nil
        }
        return Snapshot(sessionID: envelope.sessionID, messages: envelope.messages)
    }

    func save(_ messages: [Message], sessionID: Int) {
        guard let fileURL else { return }
        // 137：她那句没发稳的也存下来（App 被关掉再打开还在，还能长按重发）。
        // 还在发、没等到回执的那句也存，存成「没有发稳」：还没送到 App 就被系统关掉，重开那句还在、能重发
        // （同一个 clientID，服务器其实收到了也不会记两遍）。柯还没写完的照旧不存，重开以后没有东西能接回它们
        let confirmed = messages
            .filter {
                ($0.serverID != nil && $0.deliveryState == .sent)
                    || ($0.sender == .me && $0.clientID != nil
                        && ($0.deliveryState == .failed || $0.deliveryState == .sending))
            }
            .suffix(120)
            .map { message -> Message in
                var stored = message
                if stored.sender == .me, stored.deliveryState == .sending { stored.deliveryState = .failed }
                return stored
            }
        let envelope = Envelope(
            sessionID: sessionID,
            savedAt: .now,
            messages: Array(confirmed)
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
        } catch {
            // 缓存失败不能影响正式聊天；下一次仍从 VPS 拉取。
        }
    }
}
