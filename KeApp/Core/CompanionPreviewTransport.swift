#if DEBUG
import Foundation
import UIKit

/// 界面验收使用本地匿名响应，拦截全部请求，避免测试访问真实窗口。
final class CompanionPreviewTransport: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        if path.hasSuffix("/uploads/companion-preview.png"), let data = UIImage(named: "CamelliaSunset")?.pngData() {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"image/png"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if path.contains("/tarot/cards/"), let file = path.split(separator: "/").last,
           let real = URL(string: "https://jiagude.love/ke-test1/tarot/cards/\(file)") {
            // 牌面是公版原画，验收时从测试1 取真图；只这一类请求出网。
            let session = URLSession(configuration: .ephemeral)
            session.dataTask(with: real) { data, _, _ in
                let response = HTTPURLResponse(url: self.request.url!, statusCode: data == nil ? 404 : 200, httpVersion: nil, headerFields: ["Content-Type":"image/webp"])!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data ?? Data())
                self.client?.urlProtocolDidFinishLoading(self)
            }.resume()
            return
        }
        let body: String
        let code: Int
        if path.hasSuffix("/tarot/draw") {
            code = 200
            body = #"{"id":7,"question":"他今晚会不会来找我","spread":"three","spread_name":"三牌阵","cards":[{"position":"过去(根源/背景)","name":"The Moon","cn":"月亮","type":"Major","reversed":true,"image":"tarot/cards/major18.webp"},{"position":"现在(当下状态)","name":"Two of Cups","cn":"圣杯二","type":"Minor","reversed":false,"image":"tarot/cards/cups02.webp"},{"position":"未来(走向/建议)","name":"The Sun","cn":"太阳","type":"Major","reversed":false,"image":"tarot/cards/major19.webp"}]}"#
        }
        else if path.hasSuffix("/diary/delete"), ProcessInfo.processInfo.arguments.contains("-ui-test-diary-failure") {
            code = 503; body = #"{"error":"preview failure"}"#
        }
        else if request.httpMethod == "POST" { code = 200; body = #"{"ok":true,"id":99}"# }
        else {
            code = 200
            switch path {
            case let p where p.hasSuffix("/anniversaries"):
                body = #"[{"id":1,"name":"相识那天","date":"2025-09-09"},{"id":2,"name":"我们的纪念日","date":"2025-10-01"},{"id":3,"name":"我的生日","date":"2026-12-01"}]"#
            case let p where p.hasSuffix("/schedule"):
                body = #"{"current":[{"id":1,"text":"带上资料","scheduled_for":"2026-09-10 09:00:00","status":"pending","outcome":"","outcome_label":"","due":false}],"history":[]}"#
            case let p where p.hasSuffix("/shifts"):
                body = #"[{"date":"2026-09-09","shift":"早班+睡班","note":""},{"date":"2026-09-10","shift":"上夜","note":""}]"#
            case let p where p.hasSuffix("/periods"):
                body = #"[{"id":1,"start_date":"2026-09-07","end_date":"2026-09-11","note":""}]"#
            case let p where p.hasSuffix("/companion/intimate-counts"):
                body = #"[{"date":"2026-09-09","count":2}]"#
            case let p where p.hasSuffix("/diary"):
                let rows = [
                    #"{"id":1,"title":"匿名日记","content":"今天一起散步。","author":"佳佳","created_at":"2026-09-09 10:00:00","locked_hidden":false,"comments":0}"#,
                    #"{"id":2,"title":"枕边的一页","content":"夜色很静，月光落在窗边，\n像轻轻的问候。\n世界慢了下来，心里也柔软了许多。\n愿明天，也是好的一天。","author":"柯","created_at":"2026-09-08 23:00:00","locked_hidden":false,"comments":0}"#,
                    #"{"id":3,"title":"晚风","content":"窗外有风，心里很静。","author":"柯","created_at":"2026-08-28 20:00:00","locked_hidden":false,"comments":0}"#,
                    #"{"id":4,"title":"锁着的一页","content":"","author":"柯","created_at":"2026-08-14 20:00:00","locked_hidden":true,"comments":0}"#,
                    #"{"id":5,"title":"夏天的尾巴","content":"把这一天，轻轻收好。","author":"佳佳","created_at":"2026-08-03 20:00:00","locked_hidden":false,"comments":0}"#,
                ]
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "query" })?.value ?? ""
                if ProcessInfo.processInfo.arguments.contains("-ui-test-diary-paging"), query.isEmpty {
                    let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "offset" })?.value ?? "0"
                    if offset == "0" {
                        let pageRows: [[String: Any]] = (100..<150).map { id in
                            ["id": id, "title": "柯的日记", "content": "分页测试", "author": "柯",
                             "created_at": "2026-09-08 20:00:00", "locked_hidden": false, "comments": 0]
                        }
                        body = String(data: try! JSONSerialization.data(withJSONObject: pageRows), encoding: .utf8)!
                    } else { body = "[" + rows[0] + "]" }
                } else {
                    body = "[" + rows.filter { query.isEmpty || $0.contains(query) }.joined(separator: ",") + "]"
                }
            case let p where p.hasSuffix("/moments"):
                body = #"[{"id":1,"author":"user","content":"今天的天空很好看。","image":"/uploads/companion-preview.png","created_at":"2026-09-09 10:00:00","user_liked":0,"ai_liked":0,"comments":[]}]"#
            case let p where p.hasSuffix("/companion/records"):
                body = #"[{"id":1,"kind":"intimate","date":"2026-09-09","note":"匿名私密记录"}]"#
            default: body = "[]"
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
