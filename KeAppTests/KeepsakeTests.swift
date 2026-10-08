import XCTest
import UIKit
@testable import KeApp

@MainActor
final class KeepsakeTests: XCTestCase {
    private func item(_ id: Int, visibility: String, title: String = "标题",
                      teaser: String = "提示", content: String = "全文") -> RemoteDrawer.Item {
        RemoteDrawer.Item(id: id, title: title, teaser: teaser, content: content,
                          visibility: visibility, created_at: "2026-10-08")
    }
    func testPrivateAndUnknownVisibilityNeverReachPresentation() {
        let result = DrawerKeepsakes(RemoteDrawer(sealed: true, outside: [
            item(1, visibility: "private", title: "PRIVATE_TITLE", teaser: "PRIVATE_HINT", content: "PRIVATE_BODY"),
            item(2, visibility: "future-visibility", content: "UNKNOWN_BODY"),
            item(3, visibility: "released", content: "公开正文"),
            item(4, visibility: "teaser", title: "SECRET_TITLE", teaser: "等待公开", content: "SECRET_BODY")
        ]))
        XCTAssertEqual(result.letters, [DrawerLetter(id: 3, title: "标题", content: "公开正文", createdAt: "2026-10-08")])
        XCTAssertEqual(result.teasers, [DrawerTeaser(id: 4, text: "等待公开")])
        XCTAssertEqual(result.visibleCount, 2)
        XCTAssertFalse(String(reflecting: result).contains("PRIVATE"))
        XCTAssertFalse(String(reflecting: result).contains("SECRET"))
        XCTAssertFalse(String(reflecting: result).contains("UNKNOWN_BODY"))
    }
    func testPrivateOnlyIsAnEmptyVisibleDrawerAndDuplicateIDsAreSafe() {
        XCTAssertTrue(DrawerKeepsakes(RemoteDrawer(sealed: true, outside: [item(1, visibility: "private")])).isEmpty)
        let repeated = DrawerKeepsakes(RemoteDrawer(sealed: true, outside: [
            item(2, visibility: "released"), item(2, visibility: "released")
        ]))
        XCTAssertEqual(repeated.letters.count, 1)
    }
    func testDragReleaseDoesNotAddCurrentTranslationTwice() {
        XCTAssertEqual(DrawerTravel.target(start: 0, predictedTranslation: 40, distance: 100), 0)
        XCTAssertEqual(DrawerTravel.target(start: 1, predictedTranslation: -70, distance: 100), 0)
        XCTAssertEqual(DrawerTravel.target(start: 0, predictedTranslation: 65, distance: 100), 1)
        XCTAssertEqual(DrawerTravel.progress(start: 0, translation: -30, distance: 100), 0)
        XCTAssertEqual(DrawerTravel.progress(start: 0.9, translation: 80, distance: 100), 1)
    }
    func testLetterDatesKeepShanghaiDayAndRejectInvalidRawText() {
        XCTAssertEqual(DrawerDate.label("2026-10-07T17:30:00Z"), "2026年10月8日")
        XCTAssertEqual(DrawerDate.label("2026-10-08"), "2026年10月8日")
        XCTAssertEqual(DrawerDate.label("not a date"), "")
    }
    func testOnlyOneKeWindowUsesExistingRoutedEndpointAndCache() {
        XCTAssertEqual(ChatLine.allCases, [.test1])
        XCTAssertEqual(ChatLine.allCases[0].title, "柯")
        XCTAssertEqual(ChatLine.allCases[0].apiBaseURL.path, "/ke-test1")
        XCTAssertEqual(ChatLine.allCases[0].cacheFileName, "messages-test1.json")
    }
    func testEveryProductionCutoutIsBundledWithAlpha() throws {
        for name in ["KeepsakeCabinet", "KeepsakeUpperDrawer", "KeepsakeScroll", "KeepsakeWax", "KeepsakePaper", "KeepsakeRod", "KeepsakeNotesInterior", "MoonTarotBack"] {
            let image = try XCTUnwrap(UIImage(named: name), name)
            let cg = try XCTUnwrap(image.cgImage, name)
            XCTAssertGreaterThan(cg.width, 200, name)
            XCTAssertTrue([CGImageAlphaInfo.first, .last, .premultipliedFirst, .premultipliedLast].contains(cg.alphaInfo), name)
        }
    }
}
