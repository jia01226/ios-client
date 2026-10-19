import XCTest
@testable import KeApp

/// 124：话笺页「柯想得多深」怎么认服务器给的、怎么存、存不上怎么退回去；选模型那行的额度小字。

private final class EffortStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, text) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private func effortBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

private func settingsJSON(effort: String) -> String {
    #"{"proactive_on":true,"quiet_weekday":"23:00-08:30","quiet_weekend":"23:00-10:30","night_gap":40,"xhs_per_day":2,"effort":"\#(effort)"}"#
}

final class KeEffortTests: XCTestCase {
    private func api() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EffortStub.self]
        return APIClient(baseURL: URL(string: "https://example.invalid/ke-test2")!, configuration: configuration)
    }

    override func tearDown() { EffortStub.handler = nil; super.tearDown() }

    private func decode(_ json: String) throws -> KeProactiveSettings {
        try JSONDecoder().decode(KeProactiveSettings.self, from: Data(json.utf8))
    }

    func testEffortDecodingIsTolerantAndEmptyMeansServerDefault() throws {
        let old = try decode(#"{"proactive_on":false,"night_gap":30}"#)
        XCTAssertEqual(old.effort, "")
        XCTAssertTrue(old.effortIsDefault)
        XCTAssertEqual(old.effortLevel, .low)
        XCTAssertFalse(old.proactiveOn)

        let null = try decode(#"{"effort":null}"#)
        XCTAssertEqual(null.effortLevel, .low)
        XCTAssertTrue(null.effortIsDefault)

        let wrongType = try decode(#"{"effort":3}"#)
        XCTAssertEqual(wrongType.effort, "")

        let messy = try decode(#"{"effort":" XHigh "}"#)
        XCTAssertEqual(messy.effortLevel, .xhigh)
        XCTAssertFalse(messy.effortIsDefault)

        // 不认识的值原样留着、哪档都不亮
        let unknown = try decode(#"{"effort":"auto"}"#)
        XCTAssertEqual(unknown.effort, "auto")
        XCTAssertNil(unknown.effortLevel)

        XCTAssertEqual(KeEffort.allCases.map(\.rawValue), ["low", "medium", "high", "xhigh", "max"])
        XCTAssertEqual(KeEffort.allCases.map(\.title), ["省着想", "平常", "认真", "很认真", "最认真"])
        XCTAssertEqual(KeEffort.allCases.map(\.depth), [1, 2, 3, 4, 5])
    }

    @MainActor
    func testEffortChangeSavesPartialPatchAndRejectionRevertsWithReason() async throws {
        var posts: [[String: Any]] = []
        var serverEffort = ""
        var reject = false
        EffortStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/ke-test2/api/ke/settings")
            if request.httpMethod == "POST" {
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(effortBody(request))) as? [String: Any])
                posts.append(body)
                if reject { return (400, #"{"error":"effort 只能是 low/medium/high/xhigh/max"}"#) }
                serverEffort = body["effort"] as? String ?? serverEffort
            }
            return (200, settingsJSON(effort: serverEffort))
        }
        let store = KeWindowStore(api: api())
        await store.loadSettings()
        XCTAssertEqual(store.settings?.effortLevel, .low)
        XCTAssertEqual(store.settings?.effortIsDefault, true)

        // 点了先在页面上变过去，半秒后只把 effort 这一项发出去
        store.change(\.effort, to: KeEffort.xhigh.rawValue, key: "effort", wire: KeEffort.xhigh.rawValue)
        XCTAssertEqual(store.settings?.effortLevel, .xhigh)
        try await waitUntil { posts.count == 1 && !store.isSavingSettings }
        XCTAssertEqual(posts.first?.count, 1)
        XCTAssertEqual(posts.first?["effort"] as? String, "xhigh")
        XCTAssertEqual(store.settings?.effort, "xhigh")
        XCTAssertNil(store.settingsError)

        // 服务器不收：退回服务器上的值，「没存上」的原因留着给她看
        reject = true
        store.change(\.effort, to: KeEffort.max.rawValue, key: "effort", wire: KeEffort.max.rawValue)
        XCTAssertEqual(store.settings?.effortLevel, .max)
        try await waitUntil { posts.count == 2 && !store.isSavingSettings }
        XCTAssertEqual(store.settings?.effort, "xhigh")
        XCTAssertEqual(store.settingsError, "effort 只能是 low/medium/high/xhigh/max")

        // 下一次存成了，原因就收起来
        reject = false
        store.change(\.effort, to: KeEffort.medium.rawValue, key: "effort", wire: KeEffort.medium.rawValue)
        try await waitUntil { posts.count == 3 && !store.isSavingSettings }
        XCTAssertEqual(store.settings?.effortLevel, .medium)
        XCTAssertNil(store.settingsError)
    }

    func testCompactQuotaUsesTighterWindowAndMatchesUsedLine() {
        func group(status: String = "available", used: Double? = nil, remaining: Double? = nil,
                   windows: [ChatModelQuotaWindow] = []) -> ChatModelQuotaGroup {
            ChatModelQuotaGroup(id: "claude_1", label: "Claude 1", configured: true, available: true,
                                status: status, usedPercent: used, remainingPercent: remaining, resetAt: nil,
                                stale: false, source: "anthropic_oauth", windows: windows)
        }
        let session = ChatModelQuotaWindow(kind: "session", usedPercent: 57.6, remainingPercent: nil,
                                           windowMinutes: 300, resetAt: nil)
        let week = ChatModelQuotaWindow(kind: "week", usedPercent: 12, remainingPercent: 88,
                                        windowMinutes: 10_080, resetAt: nil)
        // 话笺上写「这 5 小时 已用 58%」，这一行就写剩 42%，两处对得上
        let both = group(windows: [session, week])
        XCTAssertEqual(both.tightestRemainingPercent, 42)
        XCTAssertEqual(both.compactRemainingText, "剩 42%")
        XCTAssertFalse(both.isRunningLow)

        let nearlyOut = group(windows: [ChatModelQuotaWindow(kind: "week", usedPercent: 93, remainingPercent: 7,
                                                             windowMinutes: 10_080, resetAt: nil)])
        XCTAssertEqual(nearlyOut.compactRemainingText, "剩 7%")
        XCTAssertTrue(nearlyOut.isRunningLow)

        XCTAssertEqual(group(remaining: 64).compactRemainingText, "剩 64%")
        XCTAssertEqual(group(status: "cooldown").compactRemainingText, "已用完")
        XCTAssertTrue(group(status: "cooldown").isRunningLow)
        XCTAssertEqual(group(status: "auth_required").compactRemainingText, "要重新登录")
        XCTAssertNil(group(status: "unknown", remaining: 50).compactRemainingText)
        XCTAssertNil(group().compactRemainingText)
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<60 where !condition() {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(condition(), "等了 3 秒还没到")
    }
}
