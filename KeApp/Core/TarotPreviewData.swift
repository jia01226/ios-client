#if DEBUG
import Foundation

/// Anonymous, local-only deals for UI verification. No live shuffle/pick mutations.
enum TarotPreviewData {
    private static let lock = NSLock()
    private static var questions: [String: String] = [:]
    private static var cardsForReading = ""
    static var readingSummary: String {
        lock.lock(); defer { lock.unlock() }
        return cardsForReading
    }

    static func response(for request: URLRequest) -> (Int, String)? {
        let path = request.url?.path ?? ""
        guard path.hasSuffix("/tarot/shuffle") || path.hasSuffix("/tarot/pick") else { return nil }
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }; data.append(bytes, count: count)
            }
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let spread = body["spread"] as? String ?? String((body["deal_id"] as? String ?? "preview-three").dropFirst(8))
        let positions = spread == "one" ? ["此刻"] : spread == "celtic" ? ["现状", "阻碍", "根源", "过去", "目标", "未来", "自己", "环境", "希望", "结果"] : spread == "night" ? ["过去·身份", "现在·关系", "未来·玩法"] : ["过去(根源/背景)", "现在(当下状态)", "未来(走向/建议)"]
        // 122：「夜里」只有 22 张大牌
        let deckSize = spread == "night" ? 22 : 78
        let result: [String: Any]
        if path.hasSuffix("/tarot/shuffle") {
            lock.lock(); questions[spread] = body["question"] as? String ?? ""; lock.unlock()
            result = ["deal_id": "preview-\(spread)", "deck_size": deckSize, "spread": spread, "spread_name": "牌阵", "positions": positions]
        } else {
            let picks = body["picks"] as? [Int] ?? []
            guard picks.count == positions.count, Set(picks).count == picks.count,
                  picks.allSatisfy({ (0..<deckSize).contains($0) }) else { return (400, #"{"error":"选牌数量或序号不对"}"#) }
            let names = ["月亮", "圣杯二", "太阳"]
            let images = ["major18.webp", "cups02.webp", "major19.webp"]
            lock.lock()
            let savedQuestion = questions[spread] ?? ""
            cardsForReading = positions.indices.map { "\(names[$0 % 3])（\($0 == 0 ? "逆位" : "正位")）" }.joined(separator: "，")
            lock.unlock()
            let columns = [("relationship", "身份"), ("emotion", "关系"), ("play", "玩法")]
            result = ["id": 7, "question": savedQuestion, "spread": spread, "spread_name": "牌阵", "objective": "匿名牌面解读", "cards": positions.enumerated().map { index, position in
                var card: [String: Any] = ["position": position, "name": "Card \(index)", "cn": names[index % 3], "type": "Major", "reversed": index == 0, "image": "tarot/cards/\(images[index % 3])"]
                if spread == "night" {
                    card["night"] = ["column": columns[index % 3].0, "label": columns[index % 3].1,
                                     "desc": "预览：一句场景", "interpret": "预览：展开后才看到的长解读"]
                }
                return card
            }]
        }
        return (200, String(data: try! JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
    }
}
#endif
