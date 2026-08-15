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

    private init() {
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
            fileURL = directory.appendingPathComponent("messages.json")
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
        let confirmed = messages
            .filter { $0.serverID != nil && $0.deliveryState == .sent }
            .suffix(120)
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
