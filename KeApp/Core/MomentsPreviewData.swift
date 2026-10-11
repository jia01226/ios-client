#if DEBUG
import Foundation

/// Anonymous, mutable feed for simulator checks; no request reaches the real feed.
enum MomentsPreviewData {
    private static let lock = NSLock()
    private static var nextMomentID = 703
    private static var nextCommentID = 803
    private static var failedPublish = false
    private static var rows: [[String: Any]] = [
        ["id": 702, "session_id": 1, "author": "user", "content": "给今天留一张照片。",
         "image": "/uploads/companion-preview.png", "visibility": "private", "reply_status": "done",
         "ai_liked": 1, "user_liked": 0, "created_at": "2026-10-11 10:30:00",
         "generated_by": "", "generation_model": "", "prompt_version": "", "comments": []],
        ["id": 701, "session_id": 1, "author": "ke", "content": "窗边的山茶开了。",
         "image": "", "visibility": "private", "reply_status": "done",
         "ai_liked": 0, "user_liked": 0, "created_at": "2026-10-11 10:00:00",
         "generated_by": "chat_ai", "generation_model": "", "prompt_version": "",
         "comments": [
            ["id": 801, "moment_id": 701, "session_id": 1, "author": "ke", "content": "留给你慢慢看。",
             "reply_status": "none", "created_at": "2026-10-11 10:01:00",
             "generated_by": "chat_ai", "generation_model": "", "prompt_version": ""],
            ["id": 802, "moment_id": 701, "session_id": 1, "author": "user", "content": "我看见啦。",
             "reply_status": "done", "created_at": "2026-10-11 10:02:00",
             "generated_by": "", "generation_model": "", "prompt_version": ""]
         ]]
    ]

    static func response(for request: URLRequest) -> (Int, String)? {
        guard ProcessInfo.processInfo.arguments.contains("-ui-test-moments") else { return nil }
        let path = request.url?.path ?? ""
        guard path.contains("/api/moments") || path.hasSuffix("/api/upload") else { return nil }
        lock.lock(); defer { lock.unlock() }
        func json(_ value: Any) -> String {
            String(data: try! JSONSerialization.data(withJSONObject: value), encoding: .utf8)!
        }
        func error(_ message: String, status: Int = 400) -> (Int, String) { (status, json(["error": message])) }

        if path.hasSuffix("/api/moments/status") {
            return (200, json(["last_ke_activity_at": "2026-10-11 10:31:00", "waiting": false]))
        }
        if path.hasSuffix("/api/moments"), request.httpMethod != "POST" { return (200, json(rows)) }
        if path.hasSuffix("/api/upload"), request.httpMethod == "POST" {
            return (200, json(["url": "/uploads/companion-preview.png", "is_image": true,
                               "can_read": false, "kind": "image", "name": "preview.png"]))
        }
        let fields = requestBody(request).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
        let content = (fields["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasSuffix("/api/moments"), request.httpMethod == "POST" {
            if ProcessInfo.processInfo.arguments.contains("-ui-test-moments-publish-failure"), !failedPublish {
                failedPublish = true
                return error("preview publish failure", status: 503)
            }
            let image = fields["image"] as? String ?? ""
            guard !content.isEmpty || !image.isEmpty else { return error("empty") }
            let id = nextMomentID; nextMomentID += 1
            rows.insert(["id": id, "session_id": 1, "author": "user", "content": content,
                         "image": image, "visibility": "private", "reply_status": "pending",
                         "ai_liked": 0, "user_liked": 0, "created_at": "2026-10-11 11:00:00",
                         "generated_by": "", "generation_model": "", "prompt_version": "", "comments": []], at: 0)
            return (200, json(["id": id, "session_id": 1, "reply_due_at": "2026-10-11 11:05:00"]))
        }
        if path.hasSuffix("/api/moments/comment") {
            guard !content.isEmpty else { return error("need content") }
            guard let index = rows.firstIndex(where: { $0["id"] as? Int == fields["moment_id"] as? Int }) else {
                return error("moment not found", status: 404)
            }
            let id = nextCommentID; nextCommentID += 1
            var comments = rows[index]["comments"] as? [[String: Any]] ?? []
            comments.append(["id": id, "moment_id": fields["moment_id"] ?? 0, "session_id": 1,
                             "author": "user", "content": content, "reply_status": "pending",
                             "created_at": "2026-10-11 11:00:00", "generated_by": "",
                             "generation_model": "", "prompt_version": ""])
            rows[index]["comments"] = comments
            return (200, json(["id": id, "session_id": 1, "reply_due_at": "2026-10-11 11:02:00"]))
        }
        if path.hasSuffix("/api/moments/comment/edit") || path.hasSuffix("/api/moments/comment/delete") {
            for index in rows.indices {
                var comments = rows[index]["comments"] as? [[String: Any]] ?? []
                guard let commentIndex = comments.firstIndex(where: { $0["id"] as? Int == fields["id"] as? Int }) else { continue }
                if path.hasSuffix("/edit") {
                    guard !content.isEmpty else { return error("need content") }
                    guard comments[commentIndex]["author"] as? String == "user" else { return error("comment not found", status: 404) }
                    comments[commentIndex]["content"] = content
                } else { comments.remove(at: commentIndex) }
                rows[index]["comments"] = comments
                return (200, json(["ok": true]))
            }
            return error("comment not found", status: 404)
        }
        guard let index = rows.firstIndex(where: { $0["id"] as? Int == fields["id"] as? Int }) else {
            return error("moment not found", status: 404)
        }
        if path.hasSuffix("/api/moments/edit") {
            guard !content.isEmpty else { return error("need content") }
            guard rows[index]["author"] as? String == "user" else { return error("moment not found", status: 404) }
            rows[index]["content"] = content
            return (200, json(["ok": true]))
        }
        if path.hasSuffix("/api/moments/like") {
            let liked = fields["liked"] as? Bool ?? false
            rows[index]["user_liked"] = liked ? 1 : 0
            return (200, json(["ok": true, "liked": liked]))
        }
        if path.hasSuffix("/api/moments/delete") {
            rows.remove(at: index)
            return (200, json(["ok": true]))
        }
        return error("unknown preview endpoint", status: 404)
    }

    private static func requestBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data(); var bytes = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count <= 0 { break }
            data.append(bytes, count: count)
        }
        return data
    }
}
#endif
