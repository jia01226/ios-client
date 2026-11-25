import Foundation

struct WatchMessage: Identifiable, Equatable {
    let id: Int
    let fromHer: Bool
    let text: String
    let createdAt: String
}

enum WatchAPIError: Error {
    case notPaired, unauthorized, badStatus(Int)
}

/// 手表直接连服务器（手机在身边时借手机的网，不在身边时用手表自己的 Wi-Fi / 蜂窝）。
struct WatchAPI {
    let baseURL: URL

    private struct Remote: Decodable {
        let id: Int
        let author: String
        let content: String
        let created_at: String?
    }

    private func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET") -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 25
        if let cookies = HTTPCookieStorage.shared.cookies(for: comps.url!), !cookies.isEmpty {
            for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                req.setValue(value, forHTTPHeaderField: field)
            }
        }
        return req
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 || http.statusCode == 403 { throw WatchAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw WatchAPIError.badStatus(http.statusCode) }
    }

    /// 最近的聊天（session_id 不传＝服务器当前那扇窗）
    func recent(limit: Int = 30) async throws -> [WatchMessage] {
        let (data, response) = try await URLSession.shared.data(
            for: request("api/messages", query: [URLQueryItem(name: "limit", value: String(limit))]))
        try check(response)
        let rows = try JSONDecoder().decode([Remote].self, from: data)
        return rows.compactMap { row in
            guard row.author == "user" || row.author == "assistant" else { return nil }
            let text = Self.clean(row.content)
            guard !text.isEmpty else { return nil }
            return WatchMessage(id: row.id, fromHer: row.author == "user", text: text, createdAt: row.created_at ?? "")
        }
    }

    /// 发一句。服务器收到就在后台开始回；这里接上了就松手，回复靠 recent() 轮询拿。
    func send(_ text: String) async throws {
        var req = request("api/chat", method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "client_msg_id": "watch-" + UUID().uuidString,
            "via": "notification",
            "supports_merge": true,
        ] as [String: Any])
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        try check(response)
        for try await _ in bytes.lines { break }
    }

    /// 柯的原文里有给 App 的暗号和小心思（<ke_…>），分条用 |||；手表上只要他说出口的话
    static func clean(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: "<ke_[a-z_]+>[\\s\\S]*?</ke_[a-z_]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<ke_[a-z_]+[^>]*/>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "|||", with: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
