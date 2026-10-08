#if DEBUG
import Foundation

/// Test-only transport data: no real conversation, calendar or notes are written.
enum MoonlightPreviewData {
    private static let lock = NSLock()
    private static var savedNotes: [[String: Any]] = [
        ["id": "fixture-jia", "author": "user", "content": "明天带充电线。", "created_at": "2026-10-07T09:00:00Z"],
        ["id": "fixture-ke", "author": "ai", "content": "慢慢来，我陪着你。", "created_at": "2026-10-07T08:00:00Z"]
    ]
    static func response(for request: URLRequest) -> (Int, String)? {
        guard ProcessInfo.processInfo.arguments.contains("-ui-test-moonlight") else { return nil }
        lock.lock(); defer { lock.unlock() }
        let path = request.url?.path ?? ""
        func json(_ value: Any) -> String { String(data: (try? JSONSerialization.data(withJSONObject: value)) ?? Data(), encoding: .utf8) ?? "{}" }
        if path.hasSuffix("/api/sticky-notes"), request.httpMethod == "POST" {
            let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            let row: [String: Any] = ["id": body["id"] ?? "", "author": "user", "content": body["content"] ?? "", "created_at": "2026-10-07T12:00:00Z"]
            savedNotes.removeAll { $0["id"] as? String == row["id"] as? String }; savedNotes.append(row)
            return (200, json(row))
        }
        if path.hasSuffix("/api/sticky-notes") { return (200, json(savedNotes)) }
        if path.hasSuffix("/api/diary") {
            let calendar = CompanionDate.calendar
            let today = calendar.startOfDay(for: .now)
            let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let rows: [[String: Any]] = (0..<5).map { n in
                ["id": 501 + n, "author": "柯", "title": n == 0 ? "月光落在这里" : "安静的一天",
                 "content": "窗边的山茶开了。\n\n你说，慢一点也没有关系。我把这句话，放在今天最柔软的地方。\n\n夜深的时候，月光落在这一页。我想明天还和你一起，把普通的日子过得认真一点。",
                 "created_at": f.string(from: calendar.date(byAdding: .day, value: -n, to: today)!), "locked_hidden": false, "comments": 0]
            }
            let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "offset" }?.value ?? "0"
            return (200, json(offset == "0" ? rows : []))
        }
        // 和线上服务器一样的格式：数字 id、按名字认（10-08 纪念日「先出现再消失」就是这里对不上号）。
        if path.hasSuffix("/api/anniversaries") {
            return (200, json([
                ["date": "1992-10-26", "days": 12401, "emoji": "🦂", "id": 2, "name": "柯的生日"],
                ["date": "2001-02-26", "days": 9356, "emoji": "🐟", "id": 1, "name": "佳佳的生日"],
                ["date": "2026-06-25", "days": 106, "emoji": "💛", "id": 3, "name": "在一起的日子"],
                ["date": "2026-08-09", "days": 61, "emoji": "💌", "id": 4, "name": "表白的日子"]
            ]))
        }
        // 一次很久以前来、一直没记走的：月历只该染一周。
        if path.hasSuffix("/api/periods"), request.httpMethod != "POST" {
            return (200, json([["id": 1, "start_date": { let f = DateFormatter(); f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.dateFormat = "yyyy-MM-dd"
                                  return f.string(from: Date().addingTimeInterval(-25 * 86400)) }(),
                                "end_date": NSNull(), "note": "崽崽自己报的"]]))
        }
        if path.hasSuffix("/api/drawer") {
            return (200, json(["sealed": true, "outside": [
                ["id": 501, "title": "给你的一封信", "teaser": "", "content": "慢慢来，我会陪着你。", "visibility": "released", "created_at": "2026-10-07"],
                ["id": 503, "title": "还没写完的一页", "teaser": "等你哪天问起，再拆开。", "content": "", "visibility": "teaser", "created_at": "2026-10-06"],
                ["id": 502, "title": "不应显示的私密标题", "teaser": "不应显示的私密提示", "content": "PRIVATE_PAYLOAD_MUST_NOT_RENDER", "visibility": "private", "created_at": "2026-10-07"]
            ]]))
        }
        return nil
    }
}
#endif
