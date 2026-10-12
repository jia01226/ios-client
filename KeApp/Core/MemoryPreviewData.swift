#if DEBUG
import Foundation

/// Offline-only anonymous fixtures. Enabled only with both companion + memory test arguments.
enum MemoryPreviewData {
    private static let lock = NSLock()
    private static var flowers: [[String: Any]] = (0..<647).map { index in
        let categories = ["约定", "关系", "生活", "身体", "喜好", "医疗", "恋爱"]
        return ["id": "fixture-\(index)", "title": "匿名记忆 \(index + 1)",
                "body": "我记得这件小事。这是界面验收用的匿名样例，不是真实记忆。",
                "quotes": ["这是一句匿名原话。"], "occurred_at": "2026-10-10 19:30",
                "written_at": "2026-10-10 23:55", "category": categories[index % categories.count],
                "importance": index % 10 + 1, "valence": Double(index % 11) / 10,
                "recall_count": 3, "state": index == 0 ? "bloom" : (index % 9 == 0 ? "fallen" : index % 4 == 0 ? "bud" : "bloom"),
                "author": index < 14 ? "ke" : "other", "loved": index == 0]
    }
    private static var quotes: [[String: Any]] = [
        ["id": 1, "message_id": 9001, "text": "匿名日常原话。", "note": "匿名备注", "scene": "daily", "created_at": "2026-10-11 20:00"],
        ["id": 2, "message_id": 9002, "text": "PRIVATE_QUOTE_HIDDEN", "note": "", "scene": "bedroom", "created_at": "2026-10-11 21:00"]
    ]
    private static var notes: [[String: Any]] = [
        ["id": "fixture-ke", "author": "ai", "content": "匿名便利贴，记得带钥匙。", "created_at": "2026-10-12", "acked": false]
    ]
    static func response(for request: URLRequest) -> (Int, String)? {
        guard ProcessInfo.processInfo.arguments.contains("-ui-test-memory") else { return nil }
        lock.lock(); defer { lock.unlock() }
        let path = request.url?.path ?? ""
        func json(_ value: Any) -> String { String(data: try! JSONSerialization.data(withJSONObject: value), encoding: .utf8)! }
        let method = request.httpMethod ?? "GET"
        if path.contains("/api/memory/"), ProcessInfo.processInfo.arguments.contains("-ui-test-memory-failure") {
            return (503, #"{"error":"offline fixture"}"#)
        }
        if path.hasSuffix("/memory/garden") {
            var rows = flowers
            if ProcessInfo.processInfo.arguments.contains("-ui-test-memory-empty") {
                rows = rows.map { var row = $0; row["author"] = "other"; return row }
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-test-memory-dense") {
                rows = rows.map { var row = $0; row["category"] = "约定"; row["author"] = "ke"; return row }
            }
            return (200, json(["categories": ["约定", "关系", "生活", "身体", "喜好", "医疗", "恋爱"], "flowers": rows]))
        }
        if path.contains("/memory/garden/"), method == "POST" {
            let pieces = path.split(separator: "/")
            let id = String(pieces[pieces.count - 2])
            if let index = flowers.firstIndex(where: { $0["id"] as? String == id }) {
                switch pieces.last {
                case "love": flowers[index]["loved"] = body(request)["loved"] as? Bool ?? false
                case "wither": flowers[index]["state"] = "withered"
                case "revive": flowers[index]["state"] = "bloom"
                default: return (400, "{}")
                }
                return (200, #"{"ok":true}"#)
            }
            return (404, "{}")
        }
        if path.hasSuffix("/memory/app-quotes") {
            if method == "POST" {
                let fields = body(request)
                let id = fields["message_id"] as? Int ?? 0
                quotes.removeAll { $0["message_id"] as? Int == id }
                quotes.append(["id": id, "message_id": id, "text": "这是最新一条回复。",
                               "note": fields["note"] as? String ?? "", "scene": "daily", "created_at": "2026-10-12 20:00"])
            }
            return (200, json(["quotes": quotes]))
        }
        if path.contains("/memory/app-quotes/"), method == "DELETE" {
            let id = Int(path.split(separator: "/").last ?? "") ?? -1
            quotes.removeAll { $0["id"] as? Int == id }
            return (200, #"{"ok":true}"#)
        }
        if path.hasSuffix("/api/sticky-notes/ack") || path.hasSuffix("/api/sticky-notes/unack") {
            if let index = notes.firstIndex(where: { $0["id"] as? String == body(request)["id"] as? String }) {
                notes[index]["acked"] = path.hasSuffix("/ack")
            }
            return (200, #"{"ok":true}"#)
        }
        if path.hasSuffix("/api/sticky-notes") { return (200, json(notes)) }
        return nil
    }
    private static func body(_ request: URLRequest) -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; data.append(buffer, count: count)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}
#endif
