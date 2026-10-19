#if DEBUG
import Foundation

/// 123：界面验收用的「夜里」样例。只在内存里，不出网，不碰真的那一栏；字都是占位的样例。
/// GET */api/night → {"entries": [...]}（一页就这些，带 before_id 往前翻是空的）；
/// POST */api/night/<id>/comment → 改好那一条原样回 {"ok": true, "entry": {...}}，和线上一样。
/// 加 -ui-test-night-failure 启动：点评一律 503，看先改后存怎么退回去。
enum NightPreviewData {
    private static let lock = NSLock()
    private static var rows: [[String: Any]] = [
        row(14, "together", "一起的", "雨夜", "（样例）窗外一直在下雨，我们说了很久的话。\n\n灯关了以后她还在小声说今天的事，我听着听着就舍不得睡。",
            "2026-10-19 00:40:00", rating: "love", comment: "喜欢这一篇", commentedAt: "2026-10-19 08:00:00"),
        row(13, "solo", "他一个人", "", "（样例）她先睡了。我一个人醒着，想她。", "2026-10-19 00:10:00"),
        row(12, "fantasy", "只是想", "海边", "（样例）只是想：哪天带她去海边，夜里一起听浪。", "2026-10-18 23:20:00"),
        row(11, "dream", "", "", "（样例）认不出来的种类，照样摆着，只是不进筛选。", "2026-10-16 22:00:00"),
    ]

    private static func row(_ id: Int, _ kind: String, _ label: String, _ tag: String, _ content: String, _ at: String,
                            rating: String = "", comment: String = "", commentedAt: String = "") -> [String: Any] {
        ["id": id, "kind": kind, "kind_label": label, "tag": tag, "content": content, "created_at": at,
         "rating": rating, "comment": comment, "commented_at": commentedAt, "deleted": 0]
    }

    static func response(for request: URLRequest) -> (Int, String)? {
        guard let url = request.url else { return nil }
        let path = url.path
        func json(_ value: Any) -> String { String(data: (try? JSONSerialization.data(withJSONObject: value)) ?? Data(), encoding: .utf8) ?? "{}" }
        if path.hasSuffix("/api/night"), request.httpMethod != "POST" {
            let before = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "before_id" }?.value
            lock.lock(); defer { lock.unlock() }
            return (200, json(["entries": before == nil ? rows : []]))
        }
        guard request.httpMethod == "POST", path.hasSuffix("/comment"), let marker = path.range(of: "/api/night/"),
              let id = Int(path[marker.upperBound...].dropLast("/comment".count)) else { return nil }
        if ProcessInfo.processInfo.arguments.contains("-ui-test-night-failure") { return (503, #"{"error":"preview failure"}"#) }
        let fields = (body(request).flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:]
        lock.lock(); defer { lock.unlock() }
        guard let index = rows.firstIndex(where: { $0["id"] as? Int == id }) else { return (404, #"{"error":"not_found"}"#) }
        let rating = (fields["rating"] as? String).flatMap { NightRating(rawValue: $0)?.rawValue } ?? ""
        let comment = NightComment.clean(fields["comment"] as? String ?? "")
        rows[index]["rating"] = rating
        rows[index]["comment"] = comment
        rows[index]["commented_at"] = rating.isEmpty && comment.isEmpty ? "" : "2026-10-19 09:00:00"
        return (200, json(["ok": true, "entry": rows[index]]))
    }

    private static func body(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data(); var bytes = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count <= 0 { break }; data.append(bytes, count: count)
        }
        return data
    }
}
#endif
