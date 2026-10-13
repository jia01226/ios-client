#if DEBUG
import Foundation

/// Anonymous, local-only deals for UI verification. No live shuffle/pick mutations.
enum TarotPreviewData {
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
        let positions = spread == "one" ? ["此刻"] : spread == "celtic" ? ["现状", "阻碍", "根源", "过去", "目标", "未来", "自己", "环境", "希望", "结果"] : ["过去(根源/背景)", "现在(当下状态)", "未来(走向/建议)"]
        let result: [String: Any]
        if path.hasSuffix("/tarot/shuffle") {
            result = ["deal_id": "preview-\(spread)", "deck_size": 78, "spread": spread, "spread_name": "牌阵", "positions": positions]
        } else {
            let picks = body["picks"] as? [Int] ?? []
            guard picks.count == positions.count, Set(picks).count == picks.count,
                  picks.allSatisfy({ (0..<78).contains($0) }) else { return (400, #"{"error":"选牌数量或序号不对"}"#) }
            let names = ["月亮", "圣杯二", "太阳"]
            let images = ["major18.webp", "cups02.webp", "major19.webp"]
            result = ["id": 7, "question": "匿名测试", "spread": spread, "spread_name": "牌阵", "objective": "匿名牌面解读", "cards": positions.enumerated().map { index, position in
                ["position": position, "name": "Card \(index)", "cn": names[index % 3], "type": "Major", "reversed": index == 0, "image": "tarot/cards/\(images[index % 3])"] as [String: Any]
            }]
        }
        return (200, String(data: try! JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
    }
}
#endif
