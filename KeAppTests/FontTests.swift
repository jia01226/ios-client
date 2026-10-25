import XCTest
import UIKit
@testable import KeApp

// 字体打包检查（原来在 QuoteNotebookTests 里；摘句本页已删，这条挪过来）
@MainActor
final class FontTests: XCTestCase {
    func testJournalFontIsBundled() {
        XCTAssertNotNil(UIFont(name: "NotoSerifSC-ExtraLight", size: 16), "Journal must not silently fall back to sans serif")
    }

    /// 霞鹜文楷拿掉了：以前选过它的，聊天字体退回默认的苹方，不能空着或崩
    func testRemovedWenKaiPreferenceFallsBackToDefaultTypeface() {
        let key = "app.chatTypeface"
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: key)
        defer {
            if let saved { defaults.set(saved, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        XCTAssertFalse(ChatTypography.all.contains { $0.id == "wenkai" })
        defaults.set("wenkai", forKey: key)
        XCTAssertEqual(Theme.shared.chatTypeface.id, "regular")
        XCTAssertEqual(Theme.shared.font.chatTypeface.postScriptName, "PingFangSC-Regular")
    }
}
