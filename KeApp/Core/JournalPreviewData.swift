#if DEBUG
import Foundation

/// Anonymous, in-memory simulator fixtures. Never used by the production session.
enum JournalPreviewData {
    private static let lock = NSLock()
    private static var periods: [[String: Any]] = [["id": 1, "start_date": "2026-09-07", "end_date": "2026-09-11", "note": ""]]
    private static var letters: [[String: Any]] = [["id": 1, "text": "这张便条是模拟器样例。", "created_at": "2026-10-06", "status": "answered", "reply": "看到了，已经记下。", "replied_at": "2026-10-06"]]

    static func response(for request: URLRequest) -> (Int, String)? {
        let path = request.url?.path ?? ""
        guard path.hasSuffix("/api/hut") || path.hasSuffix("/api/hut/letter") || path.hasSuffix("/api/periods") || path.hasSuffix("/api/periods/end") || path.hasSuffix("/api/periods/delete") else { return nil }
        lock.lock(); defer { lock.unlock() }
        let fields = (body(request).flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:]
        func json(_ value: Any) -> String { String(data: try! JSONSerialization.data(withJSONObject: value), encoding: .utf8)! }
        if path.hasSuffix("/api/periods/end") {
            guard let index = periods.firstIndex(where: { $0["id"] as? Int == fields["id"] as? Int }), let date = fields["end_date"] as? String else { return (404, "{\"error\":\"period not found\"}") }
            periods[index]["end_date"] = date
            return (200, "{\"ok\":true}")
        }
        if path.hasSuffix("/api/periods/delete") {
            periods.removeAll { $0["id"] as? Int == fields["id"] as? Int }
            return (200, "{\"ok\":true}")
        }
        if path.hasSuffix("/api/periods") {
            if request.httpMethod == "POST" {
                let id = (periods.compactMap { $0["id"] as? Int }.max() ?? 0) + 1
                periods.append(["id": id, "start_date": fields["start_date"] ?? "", "note": fields["note"] ?? ""])
                return (200, json(["id": id]))
            }
            return (200, json(periods))
        }
        if path.hasSuffix("/api/hut/letter") {
            let id = letters.count + 1
            letters.append(["id": id, "text": fields["text"] ?? "", "created_at": "2026-10-07", "status": "pending", "reply": "", "replied_at": NSNull()])
            return (200, json(["ok": true, "id": id]))
        }
        let memory: [String: Any] = ["kind": "moment", "text": "窗边留了一盏灯。", "date": "2026-10-06", "now": "灯还亮着。", "hits": 3, "recalled_at": "2026-10-07"]
        return (200, json([
            "open_items": [["id": "map-1", "text": "一起看完那本书。", "since": "2026-10-01"]],
            "recently_closed": [["id": 2, "text": "把桌边的灯修好了。", "closed_at": "2026-10-05", "note": "现在能安心看书了。"]],
            "cairn": [memory], "polaroids": [memory],
            "fact_book": [["category": "小习惯", "count": 1, "items": [memory]]],
            "floe": memory,
            "photos": [["caption": "一张山间晚霞的照片。", "said": "那天云很慢。", "date": "2026-10-04"]],
            "weather": ["facts": 12, "lines": 30, "photos": 4, "open_items": 1, "recalled_this_week": 5, "summary": "晴"],
            "letters": letters
        ]))
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
