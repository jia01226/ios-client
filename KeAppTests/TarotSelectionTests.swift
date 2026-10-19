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

    /// 120：第二下点在抬起那张身上任何地方都算点中它；同一处点两下就是抬起再放上桌。
    func testFanTapOnLiftedCardConfirmsItAnywhereOnItsFace() {
        for width in [295.0, 353.0, 400.0] as [CGFloat] {
            let height = width * TarotTableStyle.stageHeight
            let halfWidth = Double(width * TarotTableStyle.fanCardWidth / 2)
            let halfLength = halfWidth / Double(TarotTableStyle.cardAspect)
            for lifted in stride(from: 0, to: TarotFan.count, by: 7) {
                let (center, angle) = TarotFan.placement(lifted, width: width, height: height, lifted: true)
                for (u, v) in [(0.0, 0.0), (-0.9, 0.0), (0.9, 0.0), (0.0, 0.9), (0.0, -0.9), (0.9, -0.9), (-0.9, 0.9)] {
                    let across = u * halfWidth, along = v * halfLength
                    let point = CGPoint(x: center.x + CGFloat(along * cos(angle) - across * sin(angle)),
                                        y: center.y + CGFloat(along * sin(angle) + across * cos(angle)))
                    guard point.y >= height - width * TarotTableStyle.fanHitHeight else { continue }
                    XCTAssertEqual(TarotFan.card(at: point, width: width, height: height, picks: [], preview: lifted), lifted)
                }
            }
            for step in 0..<40 {
                let angle = Double.pi + Double(step) / 39 * Double.pi
                let radius = Double(width * TarotTableStyle.fanRadius)
                let point = CGPoint(x: width / 2 + CGFloat(cos(angle) * radius),
                                    y: height - width * TarotTableStyle.fanBottom + CGFloat(sin(angle) * radius))
                let first = TarotFan.card(at: point, width: width, height: height, picks: [], preview: nil)
                XCTAssertNotNil(first)
                XCTAssertEqual(TarotFan.card(at: point, width: width, height: height, picks: [], preview: first), first)
            }
        }
    }
    /// 120：认的是看到的最上面那张：按在最后一张的正中就是它，不是它左边被盖住的那几张。
    func testFanTapPicksTopVisibleCardAndSkipsPickedOnes() {
        let width: CGFloat = 353, height = width * TarotTableStyle.stageHeight
        let top = TarotFan.placement(77, width: width, height: height, lifted: false).center
        XCTAssertEqual(TarotFan.card(at: top, width: width, height: height, picks: [], preview: nil), 77)
        XCTAssertEqual(TarotFan.card(at: top, width: width, height: height, picks: [], preview: 10), 77)
        XCTAssertNotEqual(TarotFan.card(at: top, width: width, height: height, picks: [77], preview: nil), 77)
        XCTAssertNil(TarotFan.card(at: CGPoint(x: width / 2, y: 4), width: width, height: height, picks: [], preview: nil))
    }
    /// 120：左右滑一张一张往后换，抬起那张不挡路，一直能滑到最后一张。
    func testFanSlidingMovesInOrderPastTheLiftedCard() {
        let width: CGFloat = 353, height = width * TarotTableStyle.stageHeight
        var last = -1
        for step in 0..<1000 {
            let angle = Double.pi + Double(step) / 999 * Double.pi
            let radius = Double(width * TarotTableStyle.fanRadius)
            let point = CGPoint(x: width / 2 + CGFloat(cos(angle) * radius),
                                y: height - width * TarotTableStyle.fanBottom + CGFloat(sin(angle) * radius))
            guard let index = TarotFan.card(at: point, width: width, height: height, picks: [], preview: 30, liftAware: false) else { continue }
            XCTAssertGreaterThanOrEqual(index, last)
            if last >= 0 { XCTAssertLessThanOrEqual(index - last, 1) }
            last = index
        }
        XCTAssertEqual(last, 77)
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
