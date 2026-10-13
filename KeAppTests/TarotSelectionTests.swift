import XCTest
@testable import KeApp

final class TarotSelectionTests: XCTestCase {
    func testHandoffUsesLatestQuestionAndExactCastID() {
        let cast = TarotCast(id: 93, question: "旧的问题", spread: "celtic", spread_name: "凯尔特十字", cards: [], objective: nil)
        let message = cast.readingMessage(question: "  后来改的问题\n")
        XCTAssertTrue(message.contains("问的是：后来改的问题。"))
        XCTAssertTrue(message.contains("凯尔特十字")); XCTAssertTrue(message.contains("[塔罗#93]"))
        XCTAssertFalse(message.contains("旧的问题"))
        XCTAssertFalse(cast.readingMessage(question: " ").contains("问的是"))
    }

    func testPreviewSwitchAndSecondTapPreservePickOrder() {
        var selection = TarotSelection(deckSize: 78, requiredCount: 3)
        selection.tap(5)
        XCTAssertEqual(selection.preview, 5); XCTAssertEqual(selection.picks, [])
        selection.tap(40)
        XCTAssertEqual(selection.preview, 40); XCTAssertEqual(selection.picks, [])
        selection.tap(40); selection.tap(5); selection.tap(5); selection.tap(77); selection.tap(77)
        XCTAssertEqual(selection.picks, [40, 5, 77]); XCTAssertNil(selection.preview)
        selection.tap(3); selection.tap(3)
        XCTAssertEqual(selection.picks, [40, 5, 77])
    }
    func testInvalidDuplicateAndDragBack() {
        var selection = TarotSelection(deckSize: 78, requiredCount: 3)
        for i in [0, 40, 77] { selection.tap(i); selection.tap(i) }
        selection.returnCard(40)
        XCTAssertEqual(selection.picks, [0, 77])
        for i in [-1, 78, 0, 77] { selection.tap(i); selection.tap(i) }
        XCTAssertEqual(selection.picks, [0, 77]); XCTAssertNil(selection.preview)
        selection.tap(9); selection.tap(9)
        XCTAssertEqual(selection.picks, [0, 77, 9])
    }
    func testUncertainSubmissionFreezesExactRetryAndAllSpreadSizes() {
        for count in [1, 3, 10] {
            var selection = TarotSelection(deckSize: 78, requiredCount: count)
            XCTAssertFalse(selection.freeze())
            for index in 0..<count { selection.tap(index); selection.tap(index) }
            XCTAssertTrue(selection.freeze())
            selection.returnCard(0); selection.tap(50); selection.tap(50); selection.previewCard(44)
            XCTAssertEqual(selection.picks, Array(0..<count)); XCTAssertNil(selection.preview)
            XCTAssertTrue(selection.freeze()); XCTAssertTrue(selection.submitted)
        }
    }
    func testSlidingOnlyPreviews() {
        var selection = TarotSelection(deckSize: 78, requiredCount: 3)
        for index in 0..<78 { selection.previewCard(index) }
        XCTAssertEqual(selection.picks, []); XCTAssertEqual(selection.preview, 77)
        selection.tap(77); XCTAssertEqual(selection.picks, [77])
    }
    func testFullFanFitsSmallAndLargeScreensIncludingLiftedCard() {
        for width in [280.0, 350.0, 390.0] {
            for index in 0..<78 {
                let angle = Double.pi + Double(index) / 77 * Double.pi
                let rotation = angle + Double.pi / 2
                let halfWidth = width * Double(TarotTableStyle.fanCardWidth) / 2
                let halfHeight = halfWidth / Double(TarotTableStyle.cardAspect)
                for lifted in [false, true] {
                    let radius = width * Double(TarotTableStyle.fanRadius + (lifted ? TarotTableStyle.previewLift : 0))
                    let x = width / 2 + cos(angle) * radius
                    let extentX = abs(cos(rotation)) * halfWidth + abs(sin(rotation)) * halfHeight
                    XCTAssertGreaterThanOrEqual(x - extentX, 0)
                    XCTAssertLessThanOrEqual(x + extentX, width)
                }
            }
        }
    }

    func testDealIDsRetainWireTypeAndDealValidation() throws {
        for id in [#""opaque-deal""#, "123"] {
            let json = "{\"deal_id\":\(id),\"deck_size\":78,\"spread\":\"one\",\"spread_name\":\"一张\",\"positions\":[\"现在\"]}"
            let deal = try JSONDecoder().decode(TarotDeal.self, from: Data(json.utf8))
            XCTAssertTrue(deal.isValid)
            let data = try JSONEncoder().encode(TarotPickRequest(deal_id: deal.deal_id, picks: [77]))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["picks"] as? [Int], [77])
            if id == "123" { XCTAssertEqual(body["deal_id"] as? Int, 123) }
            else { XCTAssertEqual(body["deal_id"] as? String, "opaque-deal") }
        }
    }
}
