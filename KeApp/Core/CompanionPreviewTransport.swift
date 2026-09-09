#if DEBUG
import Foundation

/// 界面验收使用本地匿名响应，拦截全部请求，避免测试访问真实窗口。
final class CompanionPreviewTransport: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        let body: String
        let code: Int
        if request.httpMethod == "POST" { code = 200; body = #"{"ok":true,"id":99}"# }
        else {
            code = 200
            switch path {
            case let p where p.hasSuffix("/anniversaries"):
                body = #"[{"id":1,"name":"相识那天","date":"2025-09-09"},{"id":2,"name":"我们的纪念日","date":"2025-10-01"},{"id":3,"name":"我的生日","date":"2026-12-01"}]"#
            case let p where p.hasSuffix("/schedule"):
                body = #"{"current":[{"id":1,"text":"带上资料","scheduled_for":"2026-09-10 09:00:00","status":"pending","outcome":"","outcome_label":"","due":false}],"history":[]}"#
            case let p where p.hasSuffix("/diary"):
                body = #"[{"id":1,"title":"匿名日记","content":"今天一起散步。","author":"佳佳","created_at":"2026-09-09 10:00:00","locked_hidden":false,"comments":0}]"#
            case let p where p.hasSuffix("/moments"):
                body = #"[{"id":1,"author":"user","content":"今天的天空很好看。","created_at":"2026-09-09 10:00:00","user_liked":0,"ai_liked":0,"comments":[]}]"#
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
