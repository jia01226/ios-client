import XCTest
import SwiftUI
import UIKit
@testable import KeApp

@MainActor
final class CamelliaPaletteTests: XCTestCase {
    // 126：多了「粉白」，排第一个，也是默认
    func testFivePalettesWithBlushFirstAndNoOriginalBlue() {
        XCTAssertEqual(CamelliaPalette.allCases.map(\.rawValue), ["blush", "mist", "white", "ivory", "cream"])
        XCTAssertEqual(CamelliaPalette.allCases.map(\.label), ["粉白", "浅雾蓝", "冷白", "暖白", "浅米色"])
    }

    func testMissingAndUnknownValuesFallBackToBlush() {
        for value in ["", "blue", "deleted-palette"] {
            XCTAssertEqual(CamelliaPalette.resolve(value), .blush)
        }
    }

    func testNeverChosenMeansBlushButExplicitChoiceIsKept() throws {
        let suite = "CamelliaPaletteTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(CamelliaPalette.stored(in: defaults), .blush)
        XCTAssertFalse(CamelliaPalette.hasExplicitChoice(in: defaults))
        defaults.set("ivory", forKey: CamelliaPalette.storageKey)
        XCTAssertEqual(CamelliaPalette.stored(in: defaults), .ivory)
        XCTAssertTrue(CamelliaPalette.hasExplicitChoice(in: defaults))
    }

    func testBlushPaperAndInksMatchTheApprovedMockup() {
        let (r, g, b) = CamelliaPalette.blush.paperRGB
        XCTAssertEqual(r * 255, 255, accuracy: 0.01)
        XCTAssertEqual(g * 255, 254, accuracy: 0.01)
        XCTAssertEqual(b * 255, 254, accuracy: 0.01)
        XCTAssertEqual(hex(CamelliaPalette.blush.inks.primary), 0x564653)
        XCTAssertEqual(hex(CamelliaPalette.blush.inks.secondary), 0x7A6572)
        XCTAssertEqual(hex(CamelliaPalette.blush.inks.accent), 0x8C617A)
        // 挑过别的纸色的，字还是原来的蓝墨
        XCTAssertEqual(hex(CamelliaPalette.ivory.inks.primary), 0x3D5478)
        XCTAssertEqual(hex(CamelliaPalette.cream.inks.accent), 0x526D88)
    }

    // MARK: 126 聊天配色跟着换粉白（只在她没挑过纸色时）

    private func freshDefaults() throws -> (UserDefaults, String) {
        let suite = "BlushMigration.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    func testDefaultMoonlightPinkChatMovesToBlushOnce() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("moonlight-pink", forKey: "app.chatPalette")   // 76 版替所有人写进去的默认
        Theme.migrateChatPaletteToBlush(defaults)
        XCTAssertEqual(defaults.string(forKey: "app.chatPalette"), ChatPalette.blushID)
        // 迁过一次以后她自己再换回月光浅粉，不会被再改
        defaults.set("moonlight-pink", forKey: "app.chatPalette")
        Theme.migrateChatPaletteToBlush(defaults)
        XCTAssertEqual(defaults.string(forKey: "app.chatPalette"), "moonlight-pink")
    }

    func testFreshInstallGetsBlushChat() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        Theme.migrateChatPaletteToBlush(defaults)
        XCTAssertEqual(defaults.string(forKey: "app.chatPalette"), ChatPalette.blushID)
        XCTAssertEqual(ChatPalette.all.first?.id, ChatPalette.blushID)
    }

    func testExplicitChatOrPaperChoiceIsNotClobbered() throws {
        let (a, suiteA) = try freshDefaults()
        defer { a.removePersistentDomain(forName: suiteA) }
        a.set("champagne", forKey: "app.chatPalette")
        Theme.migrateChatPaletteToBlush(a)
        XCTAssertEqual(a.string(forKey: "app.chatPalette"), "champagne")

        let (b, suiteB) = try freshDefaults()
        defer { b.removePersistentDomain(forName: suiteB) }
        b.set("moonlight-pink", forKey: "app.chatPalette")
        b.set("ivory", forKey: CamelliaPalette.storageKey)   // 她自己挑过暖白
        Theme.migrateChatPaletteToBlush(b)
        XCTAssertEqual(b.string(forKey: "app.chatPalette"), "moonlight-pink")
        XCTAssertEqual(b.string(forKey: CamelliaPalette.storageKey), "ivory")
    }

    func testBlushChatPaletteUsesMockupInkAndWhiteSendGlyph() throws {
        let blush = try XCTUnwrap(ChatPalette.all.first { $0.id == ChatPalette.blushID })
        XCTAssertEqual(blush.name, "粉白")
        XCTAssertEqual(blush.base, 0xFFFEFE)
        XCTAssertEqual(blush.ink, 0x564653)
        XCTAssertEqual(blush.secondary, 0x7A6572)
        XCTAssertEqual(blush.accent, 0x8C617A)
        XCTAssertTrue(blush.clearBubbles)
        let palette = Palette.chat(blush)
        XCTAssertEqual(hex(palette.textOnAccent), 0xFFFFFF)
        XCTAssertEqual(hex(palette.textSecondary), 0x7A6572)
        // 原来几款不受影响
        let moon = try XCTUnwrap(ChatPalette.all.first { $0.id == "moonlight-pink" })
        XCTAssertFalse(moon.clearBubbles)
        XCTAssertEqual(hex(Palette.chat(moon).textOnAccent), Morandi.ink)
    }

    private func hex(_ color: Color) -> UInt32 {
        let c = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32((r * 255).rounded()) << 16) | (UInt32((g * 255).rounded()) << 8) | UInt32((b * 255).rounded())
    }

    func testPalettesRoundTripThroughLocalPreferences() throws {
        let suite = "CamelliaPaletteTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for palette in CamelliaPalette.allCases {
            defaults.set(palette.rawValue, forKey: CamelliaPalette.storageKey)
            XCTAssertEqual(CamelliaPalette.resolve(defaults.string(forKey: CamelliaPalette.storageKey) ?? ""), palette)
        }
    }

    func testColorComponentsAndMistStayInRange() {
        for palette in CamelliaPalette.allCases {
            let (r, g, b) = palette.paperRGB
            XCTAssertTrue([r, g, b].allSatisfy { (0.85...1).contains($0) })
            XCTAssertTrue((0...1).contains(palette.mistOpacity))
            XCTAssertTrue((0...1).contains(palette.mistSaturation))
        }
        XCTAssertEqual(CamelliaPalette.cream.paperRGB.0, 244.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(CamelliaPalette.white.mistSaturation, 0)
    }
}
