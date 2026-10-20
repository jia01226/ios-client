import XCTest
import SwiftUI
@testable import KeApp

/// 127：滑聊天不卡——玻璃透度、她自己挑的气泡、时间线条目缓存
@MainActor
final class SmoothChatTests: XCTestCase {
    private func freshDefaults() throws -> (UserDefaults, String) {
        let suite = "SmoothChat.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    // MARK: 玻璃透度

    func testGlassClarityMigratesOnlyExplicitOldChoices() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        // 从没在素笺里点过：不写，走新默认
        KeGlassClarity.migrate(defaults)
        XCTAssertNil(defaults.object(forKey: KeGlassClarity.storageKey))

        defaults.set(KeGlassLevel.paper.rawValue, forKey: KeGlassLevel.storageKey)
        KeGlassClarity.migrate(defaults)
        XCTAssertEqual(defaults.double(forKey: KeGlassClarity.storageKey), 0)

        // 搬过一次以后不再动她拖过的值
        defaults.set(0.4, forKey: KeGlassClarity.storageKey)
        defaults.set(KeGlassLevel.float.rawValue, forKey: KeGlassLevel.storageKey)
        KeGlassClarity.migrate(defaults)
        XCTAssertEqual(defaults.double(forKey: KeGlassClarity.storageKey), 0.4)
    }

    func testGlassClarityPresetsAndReadableFloor() {
        XCTAssertEqual(KeGlassClarity.preset(.paper), 0)
        XCTAssertEqual(KeGlassClarity.preset(.light), 0.55)
        XCTAssertEqual(KeGlassClarity.preset(.float), 0.85)
        // 纸色 = 1 − 透度，有字的表面不低于 minPaper
        XCTAssertEqual(KeGlassClarity.paperOpacity(clarity: 0.75, minPaper: 0.2), 0.25, accuracy: 0.0001)
        XCTAssertEqual(KeGlassClarity.paperOpacity(clarity: 1, minPaper: 0.2), 0.2, accuracy: 0.0001)
        XCTAssertEqual(KeGlassClarity.paperOpacity(clarity: 0.5, minPaper: 0.72), 0.72, accuracy: 0.0001)
        XCTAssertEqual(KeGlassClarity.clamp(.nan), KeGlassClarity.defaultValue)
        XCTAssertEqual(KeGlassClarity.clamp(3), 1)
    }

    // MARK: 气泡

    func testBubbleDefaultsFollowTheMockup() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        // 128：QQ 那样实心，她的粉深一点点
        XCTAssertEqual(BubbleStyleStore.loadHex(.me, defaults), 0xF3DDE4)
        XCTAssertEqual(BubbleStyleStore.loadHex(.ke, defaults), 0xFFFFFF)
        XCTAssertEqual(BubbleStyleStore.loadDensity(.me, defaults), 1.0)
        XCTAssertEqual(BubbleStyleStore.loadDensity(.ke, defaults), 1.0)
        // 旧的「气泡透明度」不影响新浓度
        defaults.set(0.012, forKey: "app.bubbleOpacity")
        XCTAssertEqual(BubbleStyleStore.loadDensity(.me, defaults), 1.0)
    }

    func testBubbleStoredValuesAreClampedAndBadOnesIgnored() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Int(Morandi.own), forKey: BubbleStyleStore.meColorKey)
        defaults.set(1.7, forKey: BubbleStyleStore.meDensityKey)
        defaults.set(-5, forKey: BubbleStyleStore.keColorKey)
        defaults.set("oops", forKey: BubbleStyleStore.keDensityKey)
        XCTAssertEqual(BubbleStyleStore.loadHex(.me, defaults), Morandi.own)
        XCTAssertEqual(BubbleStyleStore.loadDensity(.me, defaults), 1)
        XCTAssertEqual(BubbleStyleStore.loadHex(.ke, defaults), 0xFFFFFF)
        XCTAssertEqual(BubbleStyleStore.loadDensity(.ke, defaults), 1.0)
    }

    func testMoonlightSwatchIsBuild125Pink() throws {
        let moon = try XCTUnwrap(BubbleSwatch.all.first { $0.id == "moonlight" })
        XCTAssertEqual(moon.me, Morandi.own)
        XCTAssertEqual(moon.ke, Morandi.reply)
        XCTAssertEqual(BubbleSwatch.matching(0xF3DDE4, side: .me)?.id, "blush")
        XCTAssertNil(BubbleSwatch.matching(0x123456, side: .ke))
        XCTAssertEqual(Color(hex: 0xF6E8EC).rgbHex, 0xF6E8EC)
    }

    // MARK: 时间线条目缓存

    func testTimelineCacheReusesItemsUntilInputsChange() {
        let cache = ChatTimelineItemsCache()
        let messages = [
            Message(id: "a", serverID: 1, sender: .me, text: "在吗", time: .now),
            Message(id: "b", serverID: 2, sender: .ke, text: "在。", time: .now),
        ]
        func build(_ messages: [Message], highlighted: String? = nil, reveal: [String: Int]? = [:]) -> [ChatTimelineItem] {
            cache.items(messages: messages, highlightedMessageID: highlighted, quotedIDs: [], pinnedIDs: [],
                        revealCounts: reveal, visibleSegmentCount: { _ in nil })
        }
        let first = build(messages)
        XCTAssertEqual(cache.rebuildCount, 1)
        XCTAssertEqual(build(messages), first)
        XCTAssertEqual(cache.rebuildCount, 1)

        _ = build(messages, highlighted: "b")
        XCTAssertEqual(cache.rebuildCount, 2)

        var more = messages
        more.append(Message(id: "c", serverID: 3, sender: .me, text: "好", time: .now))
        let grown = build(more, highlighted: "b")
        XCTAssertEqual(cache.rebuildCount, 3)
        XCTAssertEqual(grown, ChatTimelineItem.make(messages: more, highlightedMessageID: "b", visibleSegmentCount: { _ in nil }))

        _ = build(more, highlighted: "b", reveal: ["x": 1])
        XCTAssertEqual(cache.rebuildCount, 4)
    }
}
