import XCTest
import UIKit
@testable import KeApp

// 字体打包检查（原来在 QuoteNotebookTests 里；摘句本页已删，这条挪过来）
@MainActor
final class FontTests: XCTestCase {
    func testJournalFontIsBundled() {
        XCTAssertNotNil(UIFont(name: "NotoSerifSC-ExtraLight", size: 16), "Journal must not silently fall back to sans serif")
    }
}
