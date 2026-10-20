import XCTest
import SwiftUI
@testable import KeApp

/// 128：滑消息不回跳、QQ 那样的平气泡、「夜里日记」卡、小红书链接、气泡不再等缓冲
@MainActor
final class QQChatTests: XCTestCase {
    private func freshDefaults() throws -> (UserDefaults, String) {
        let suite = "QQChat.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    // MARK: 滑动：她在滑的时候程序不挪列表

    func testFollowIsDeferredWhileUserScrolls() {
        XCTAssertTrue(ChatTimelineScrollGate.userIsScrolling(isTracking: true, isDragging: false, isDecelerating: false))
        XCTAssertTrue(ChatTimelineScrollGate.userIsScrolling(isTracking: false, isDragging: false, isDecelerating: true))
        XCTAssertFalse(ChatTimelineScrollGate.userIsScrolling(isTracking: false, isDragging: false, isDecelerating: false))

        // 没在滑：照落
        let idle = ChatTimelineScrollGate.resolveFollow(wantsFollow: true, userIsScrolling: false)
        XCTAssertTrue(idle.followNow); XCTAssertFalse(idle.followLater)
        // 在滑：现在不落，记着
        let busy = ChatTimelineScrollGate.resolveFollow(wantsFollow: true, userIsScrolling: true)
        XCTAssertFalse(busy.followNow); XCTAssertTrue(busy.followLater)
        // 本来就不落：什么都不记
        let none = ChatTimelineScrollGate.resolveFollow(wantsFollow: false, userIsScrolling: true)
        XCTAssertFalse(none.followNow); XCTAssertFalse(none.followLater)
    }

    func testDeferredFollowOnlyLandsWhenStoppedNearLatest() {
        XCTAssertTrue(ChatTimelineScrollGate.shouldFollowAfterScrollEnds(followLater: true, isNearLatest: true))
        // 她往上翻走了：不拽回去
        XCTAssertFalse(ChatTimelineScrollGate.shouldFollowAfterScrollEnds(followLater: true, isNearLatest: false))
        XCTAssertFalse(ChatTimelineScrollGate.shouldFollowAfterScrollEnds(followLater: false, isNearLatest: true))
    }

    /// 回跳的根：同一行在复用的格子上量，一会儿 161 一会儿 73。现在同一行同一版内容同样宽只量一次，之后一直是这个数
    func testRowHeightCacheKeepsOneHeightPerRowVersion() {
        var cache = ChatRowHeightCache<String>()
        cache.resetIfNeeded(signature: "15|regular|L")
        XCTAssertNil(cache.height(id: "a::message", content: "v1", width: 358))
        cache.store(id: "a::message", content: "v1", width: 358, height: 212)
        cache.store(id: "b::message", content: "v1", width: 358, height: 64)
        XCTAssertEqual(cache.height(id: "a::message", content: "v1", width: 358), 212)
        XCTAssertEqual(cache.height(id: "a::message", content: "v1", width: 358.3), 212, "小数点上的差不算换了宽")
        XCTAssertNil(cache.height(id: "a::message", content: "v1", width: 300), "宽变了（转屏）就重新量")
        XCTAssertNil(cache.height(id: "a::message", content: "v2", width: 358), "内容变了重新量")
        XCTAssertEqual(cache.estimate(id: "a::message", width: 358), 212, "估的时候先按上次的")
        // 坏的量法不记
        cache.store(id: "c::message", content: "v1", width: 0, height: 50)
        cache.store(id: "d::message", content: "v1", width: 358, height: .infinity)
        XCTAssertEqual(cache.count, 2)
        // 时间线里没有了的行拿掉
        cache.prune(keeping: ["b::message"])
        XCTAssertNil(cache.estimate(id: "a::message", width: 358))
        XCTAssertEqual(cache.estimate(id: "b::message", width: 358), 64)
        // 字号换了：都不算数
        cache.resetIfNeeded(signature: "15|regular|L")
        XCTAssertEqual(cache.count, 1)
        cache.resetIfNeeded(signature: "18|regular|L")
        XCTAssertEqual(cache.count, 0)
    }

    /// 量尺：同一行量几次都是同一个数（不跟着格子当时多高走），字多的更高
    func testRowSizerIsDeterministic() {
        let sizer = ChatRowSizer()
        func row(_ text: String) -> AnyView {
            AnyView(MessageRow(message: Message(id: "x", sender: .ke, text: text, time: .now),
                               isHighlighted: false, visibleSegmentCount: nil, onAttachmentTap: { _ in })
                .environmentObject(Theme.shared))
        }
        let short = sizer.height(of: row("嗯。"), width: 358)
        let again = sizer.height(of: row("嗯。"), width: 358)
        let long = sizer.height(of: row(String(repeating: "前面的回复，用来把聊天列表撑过一屏。", count: 6)), width: 358)
        XCTAssertGreaterThan(short, 20)
        XCTAssertEqual(short, again)
        XCTAssertGreaterThan(long, short + 40)
        XCTAssertEqual(sizer.height(of: row("嗯。"), width: 358), short, "量过长的再量短的，还是原来的数")
    }

    func testOnlySelfGrowingRowsAreMeasuredOnTheCell() {
        let plain = Message(id: "p", sender: .ke, text: "嗯", time: .now)
        let night = Message(id: "n", sender: .ke, text: "夜里日记 · 刚才那一回", time: .now,
                            attachments: [ChatAttachment(url: "ke-night://41", name: "", kind: "night")])
        XCTAssertTrue(ChatCollectionTimelineController.isStaticallySized(ChatTimelineItem(kind: .message, message: plain, isHighlighted: false)))
        XCTAssertTrue(ChatCollectionTimelineController.isStaticallySized(ChatTimelineItem(kind: .date("2026-10-20"), message: plain, isHighlighted: false)))
        XCTAssertFalse(ChatCollectionTimelineController.isStaticallySized(ChatTimelineItem(kind: .message, message: night, isHighlighted: false)))
        XCTAssertFalse(ChatCollectionTimelineController.isStaticallySized(ChatTimelineItem(kind: .tool("t1"), message: plain, isHighlighted: false)))
    }

    // MARK: 气泡：深色自动白字、默认实心

    func testDarkCustomBubbleGetsWhiteText() {
        let ink: UInt32 = 0x4C4056
        let page: UInt32 = 0xFBF3F5
        // 她挑了深色（酒红、墨蓝、纯黑）：白字
        XCTAssertTrue(BubbleInk.usesLightText(fill: 0x7A2E45, density: 1, backdrop: page, darkInk: ink))
        XCTAssertTrue(BubbleInk.usesLightText(fill: 0x1F2A44, density: 1, backdrop: page, darkInk: ink))
        XCTAssertTrue(BubbleInk.usesLightText(fill: 0x000000, density: 1, backdrop: page, darkInk: ink))
        // 默认的粉和白、浅色：墨色字
        XCTAssertFalse(BubbleInk.usesLightText(fill: 0xF3DDE4, density: 1, backdrop: page, darkInk: ink))
        XCTAssertFalse(BubbleInk.usesLightText(fill: 0xFFFFFF, density: 1, backdrop: page, darkInk: ink))
        XCTAssertFalse(BubbleInk.usesLightText(fill: 0xD7CAB6, density: 1, backdrop: page, darkInk: ink))
        // 深色但浓度很低：屏幕上是浅的，照旧墨色字
        XCTAssertFalse(BubbleInk.usesLightText(fill: 0x1F2A44, density: 0.1, backdrop: page, darkInk: ink))
        XCTAssertEqual(BubbleInk.composite(0x000000, density: 0.5, over: 0xFFFFFF), 0x808080)
        XCTAssertEqual(BubbleInk.relativeLuminance(0xFFFFFF), 1, accuracy: 0.0001)
        XCTAssertEqual(BubbleInk.contrast(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
    }

    func testOldDensitiesMigrateToSolidOnce() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0.6, forKey: BubbleStyleStore.meDensityKey)
        defaults.set(0.45, forKey: BubbleStyleStore.keDensityKey)
        defaults.set(Int(0xF6E8EC), forKey: BubbleStyleStore.meColorKey)
        defaults.set(Int(0x2B2B2B), forKey: BubbleStyleStore.keColorKey)
        BubbleStyleStore.migrateToSolid(defaults)
        XCTAssertEqual(BubbleStyleStore.loadDensity(.me, defaults), 1)
        XCTAssertEqual(BubbleStyleStore.loadDensity(.ke, defaults), 1)
        XCTAssertEqual(BubbleStyleStore.loadHex(.me, defaults), 0xF3DDE4, "127 默认的淡粉换成 128 的粉")
        XCTAssertEqual(BubbleStyleStore.loadHex(.ke, defaults), 0x2B2B2B, "她自己挑的颜色不动")
        // 只搬一次：之后她再拖的值留着
        defaults.set(0.3, forKey: BubbleStyleStore.meDensityKey)
        BubbleStyleStore.migrateToSolid(defaults)
        XCTAssertEqual(BubbleStyleStore.loadDensity(.me, defaults), 0.3)
    }

    func testSegmentRevealIsSnappy() {
        let motion = MotionTokens()
        XCTAssertEqual(motion.splitBubbleInterval(forCount: 1), 0)
        XCTAssertEqual(motion.splitBubbleInterval(forCount: 2), 0.12, accuracy: 0.0001)
        // 切得再多，第一个到最后一个加起来不超过半秒
        for count in 2...12 {
            let total = motion.splitBubbleInterval(forCount: count) * Double(count - 1)
            XCTAssertLessThanOrEqual(total, 0.5 + 0.0001)
        }
    }

    // MARK: 夜里日记卡

    private let nightKey = ChatAttachment(url: "ke-night://41", name: "浴室", kind: "night")

    func testNightCardIsRecognizedAndIsOneRow() {
        XCTAssertEqual(nightKey.nightID, 41)
        XCTAssertNil(nightKey.diaryID)
        XCTAssertNil(ChatAttachment(url: "ke-night://41", name: "", kind: "file").nightID)
        XCTAssertNil(ChatAttachment(url: "ke-diary://41", name: "", kind: "night").nightID)
        XCTAssertNil(ChatAttachment(url: "ke-night://abc", name: "", kind: "night").nightID)

        // 服务器切了气泡也不切：整条一张卡
        let card = Message(id: "n", serverID: 605, sender: .ke, text: "夜里日记 · 刚才那一回\n\n多一段",
                           time: .now, attachments: [nightKey], segments: ["夜里日记 · 刚才那一回", "多一段"])
        XCTAssertEqual(card.nightCard?.nightID, 41)
        XCTAssertTrue(card.isCardMessage)
        XCTAssertEqual(card.bubbleSegments.count, 1)
        let rows = ChatTimelineItem.make(message: card, isHighlighted: false, visibleSegmentCount: nil)
        XCTAssertEqual(rows.map(\.kind), [.message])

        // 她发的、普通附件都不是卡
        XCTAssertNil(Message(id: "m", sender: .me, text: "", time: .now, attachments: [nightKey]).nightCard)
        XCTAssertFalse(Message(id: "p", sender: .ke, text: "a\n\nb", time: .now).isCardMessage)

        XCTAssertEqual(NightDiaryCard.title(card), "夜里日记 · 刚才那一回")
        XCTAssertEqual(NightDiaryCard.title(Message(id: "e", sender: .ke, text: "", time: .now)), NightDiaryCard.defaultTitle)
        XCTAssertEqual(NightDiaryCard.excerpt(nil, fallback: "浴室"), "浴室")
        XCTAssertEqual(NightDiaryCard.excerpt(RemoteNight(id: 41, content: "第一行\n第二行"), fallback: "浴室"), "第一行 第二行")
    }

    /// 旧版本、以后的新种类：附件少给字段也不让整条消息解不开
    func testAttachmentDecodingIsTolerant() throws {
        let json = #"[{"url":"ke-night://41","name":"浴室","kind":"night"},{"url":"ke-night://42"},{"url":"/u/a.jpg","name":"a.jpg","kind":"image","extra":1}]"#
        let list = try JSONDecoder().decode([ChatAttachment].self, from: Data(json.utf8))
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list[0].nightID, 41)
        XCTAssertEqual(list[1].name, "")
        XCTAssertNil(list[1].nightID, "没写 kind 的不当夜里卡")
        XCTAssertTrue(list[2].isImage)
        // 存进缓存再读出来一样
        let again = try JSONDecoder().decode([ChatAttachment].self, from: JSONEncoder().encode(list))
        XCTAssertEqual(again, list)
    }

    func testDiaryOpensOnNightTabFromNightCard() {
        XCTAssertEqual(DiaryTab.current(saved: "diary", pinnedToDiary: false, pinnedToNight: true), .night)
        XCTAssertEqual(DiaryTab.current(saved: "night", pinnedToDiary: true), .diary)
        XCTAssertEqual(NightPane.anchor(41), "night-entry-41")
    }

    // MARK: 下回想要

    func testNightPrefsToggleCleanAndBody() throws {
        var prefs: [String: String] = [:]
        prefs = NightPref.toggled(prefs, .pace, "slower")
        prefs = NightPref.toggled(prefs, .after, "cuddle")
        XCTAssertEqual(prefs, ["pace": "slower", "after": "cuddle"])
        prefs = NightPref.toggled(prefs, .pace, "faster")
        XCTAssertEqual(prefs["pace"], "faster", "同一行点别的换掉")
        prefs = NightPref.toggled(prefs, .pace, "faster")
        XCTAssertNil(prefs["pace"], "再点一下取消")
        XCTAssertEqual(NightPref.clean(["pace": "warp", "mood": "x", "talk": "less"]), ["talk": "less"])
        XCTAssertEqual(NightPref.after.options.map(\.value), ["cuddle", "ok"])
        XCTAssertEqual(NightPref.foreplay.label(for: "skip"), "直接来")

        let body = NightComment.body(rating: .love, comment: " 好\n喜欢 ", prefs: ["force": "harder", "bogus": "1"])
        XCTAssertEqual(body["rating"] as? String, "love")
        XCTAssertEqual(body["comment"] as? String, "好 喜欢")
        XCTAssertEqual(body["prefs"] as? [String: String], ["force": "harder"])
        let empty = NightComment.body(rating: nil, comment: "", prefs: [:])
        XCTAssertEqual(empty["prefs"] as? [String: String], [:])
    }

    func testRemoteNightDecodesPrefsLossily() throws {
        let json = #"{"entries":[{"id":1,"prefs":{"pace":"slower","force":3,"talk":"loud"}},{"id":2,"prefs":null},{"id":3}]}"#
        let page = try JSONDecoder().decode(NightPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.entries.map(\.id), [1, 2, 3])
        XCTAssertEqual(page.entries[0].prefs, ["pace": "slower"])
        XCTAssertEqual(page.entries[1].prefs, [:])
        XCTAssertEqual(page.entries[2].prefs, [:])
    }

    func testStoreSendsPrefsWithRatingAndNote() async throws {
        let fake = PrefsFake(entry: RemoteNight(id: 41, rating: "ok", comment: "还行"))
        let store = NightStore(service: fake)
        await store.load()
        await store.setPref(41, .pace, "slower")
        var sent = await fake.sent
        XCTAssertEqual(sent.last?.rating, "ok")
        XCTAssertEqual(sent.last?.comment, "还行")
        XCTAssertEqual(sent.last?.prefs, ["pace": "slower"])
        XCTAssertEqual(store.entry(41)?.prefs, ["pace": "slower"])

        // 点评价、写备注都带着「下回想要」一起发
        await store.rate(41, .love)
        sent = await fake.sent
        XCTAssertEqual(sent.last?.rating, "love")
        XCTAssertEqual(sent.last?.prefs, ["pace": "slower"])
        store.drafts[41] = "下次还要"
        await store.send(41)
        sent = await fake.sent
        XCTAssertEqual(sent.last?.comment, "下次还要")
        XCTAssertEqual(sent.last?.prefs, ["pace": "slower"])
        XCTAssertEqual(store.entry(41)?.comment, "下次还要")

        // 再点一下取消
        await store.setPref(41, .pace, "slower")
        sent = await fake.sent
        XCTAssertEqual(sent.last?.prefs, [:])
    }

    func testCardLoadsEntryOnlyOnce() async {
        let fake = PrefsFake(entry: RemoteNight(id: 41))
        let store = NightStore(service: fake)
        await store.ensure(99)   // 不在第一页
        await store.ensure(99)   // 不再拉
        await store.ensure(41)   // 已经在手上
        let fetches = await fake.fetches
        XCTAssertEqual(fetches, 1)
        XCTAssertNotNil(store.entry(41))
    }

    // MARK: 小红书链接

    func testXiaohongshuLinksOpenTheNote() throws {
        let shared = try XCTUnwrap(URL(string: "https://www.xiaohongshu.com/explore/6aba0339000000001802e795?xsec_token=ABem2UZRMkV4EO-7cAEnl88OJQVsmV523bgPl-Xjy83-Y=&xsec_source=pc_feed"))
        XCTAssertEqual(ChatLinks.xhsNote(shared), .init(id: "6aba0339000000001802e795", token: "ABem2UZRMkV4EO-7cAEnl88OJQVsmV523bgPl-Xjy83-Y="))
        let targets = try XCTUnwrap(ChatLinks.xhsTargets(shared))
        XCTAssertEqual(targets.app.absoluteString, "xhsdiscover://item/6aba0339000000001802e795")
        XCTAssertEqual(
            targets.web.absoluteString,
            "https://www.xiaohongshu.com/discovery/item/6aba0339000000001802e795?xsec_token=ABem2UZRMkV4EO-7cAEnl88OJQVsmV523bgPl-Xjy83-Y%3D&xsec_source=app_share"
        )
        // token 编码以后读回来还是原样
        let back = URLComponents(url: targets.web, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "xsec_token" }?.value
        XCTAssertEqual(back, "ABem2UZRMkV4EO-7cAEnl88OJQVsmV523bgPl-Xjy83-Y=")

        let item = try XCTUnwrap(URL(string: "https://xiaohongshu.com/discovery/item/abc123"))
        XCTAssertEqual(ChatLinks.xhsTargets(item)?.web.absoluteString,
                       "https://www.xiaohongshu.com/discovery/item/abc123?xsec_source=app_share")

        // 短链接、别的页、别的网站：照原样打开
        XCTAssertNil(ChatLinks.xhsTargets(try XCTUnwrap(URL(string: "https://xhslink.com/a/AbCd"))))
        XCTAssertNil(ChatLinks.xhsTargets(try XCTUnwrap(URL(string: "https://www.xiaohongshu.com/user/profile/123"))))
        XCTAssertNil(ChatLinks.xhsTargets(try XCTUnwrap(URL(string: "https://notxiaohongshu.com/explore/abc"))))
        XCTAssertNil(ChatLinks.xhsTargets(try XCTUnwrap(URL(string: "https://x.com/explore/abc"))))
    }
}

private actor PrefsFake: NightDiaryService {
    struct Sent: Equatable { let rating: String; let comment: String; let prefs: [String: String] }
    private var entry: RemoteNight
    private(set) var sent: [Sent] = []
    private(set) var fetches = 0

    init(entry: RemoteNight) { self.entry = entry }

    func fetchNight(limit: Int, beforeID: Int?) async throws -> [RemoteNight] {
        fetches += 1
        return beforeID == nil ? [entry] : []
    }
    func commentNight(id: Int, rating: NightRating?, comment: String) async throws -> RemoteNight {
        try await commentNight(id: id, rating: rating, comment: comment, prefs: [:])
    }
    func commentNight(id: Int, rating: NightRating?, comment: String, prefs: [String: String]) async throws -> RemoteNight {
        sent.append(Sent(rating: rating?.rawValue ?? "", comment: comment, prefs: prefs))
        entry.rating = rating?.rawValue ?? ""
        entry.comment = comment
        entry.prefs = prefs
        return entry
    }
}
