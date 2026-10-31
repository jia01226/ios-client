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

    // MARK: - 122：「夜里」

    /// 122：夜里交给柯的那句一字不差，不带问题；[塔罗#id] 照旧
    func testNightHandoffMessageIsExactAndIgnoresQuestion() {
        let cast = TarotCast(id: 4321, question: "", spread: "night", spread_name: "夜里", cards: [], objective: nil)
        XCTAssertEqual(cast.readingMessage(question: ""), "爸比，今晚抽了「夜里」。 [塔罗#4321]")
        XCTAssertEqual(cast.readingMessage(question: "  别的牌阵留下的问题 "), "爸比，今晚抽了「夜里」。 [塔罗#4321]")
        // 别的牌阵不受影响
        let three = TarotCast(id: 5, question: "", spread: "three", spread_name: "三张", cards: [], objective: nil)
        XCTAssertEqual(three.readingMessage(question: ""), "爸比，我抽了三张，帮我断断。 [塔罗#5]")
    }

    /// 122：夜里的牌面带 night 一段；旧牌阵没有这段照样解得出来，night 是 nil
    func testNightCastDecodesNightFieldsAndOlderCastsStayNil() throws {
        let json = #"""
        {"id": 88, "question": "", "spread": "night", "spread_name": "夜里", "cards": [
          {"position": "过去·身份", "name": "The Fool", "cn": "愚者", "type": "major", "reversed": false, "image": "tarot/cards/major00.webp",
           "night": {"column": "relationship", "label": "身份", "desc": " 第一次的新手情侣 ", "interpret": "一个全新的开始。"}},
          {"position": "现在·关系", "name": "The Moon", "cn": "月亮", "type": "major", "reversed": true, "image": "tarot/cards/major18.webp",
           "night": {"column": "emotion", "label": "关系", "desc": "若即若离", "interpret": "看不清的那一段。", "extra": 1}},
          {"position": "未来·玩法", "name": "The Sun", "cn": "太阳", "type": "major", "reversed": false, "image": "tarot/cards/major19.webp",
           "night": {"column": "play", "label": "玩法", "desc": "白天的游戏", "interpret": "放开玩。"}}
        ]}
        """#
        let cast = try JSONDecoder().decode(TarotCast.self, from: Data(json.utf8))
        XCTAssertEqual(cast.spread, "night"); XCTAssertNil(cast.objective)
        XCTAssertEqual(cast.cards.map { $0.night?.label }, ["身份", "关系", "玩法"])
        XCTAssertEqual(cast.cards.map { $0.night?.column }, ["relationship", "emotion", "play"])
        XCTAssertEqual(cast.cards[0].night?.desc, "第一次的新手情侣")
        XCTAssertEqual(cast.cards[0].night?.summary, "第一次的新手情侣")
        XCTAssertEqual(cast.cards[0].night?.more, "一个全新的开始。")
        XCTAssertTrue(cast.cards[1].reversed)
        XCTAssertEqual(cast.readingMessage(question: ""), "爸比，今晚抽了「夜里」。 [塔罗#88]")

        let old = #"""
        {"id": 9, "question": "q", "spread": "three", "spread_name": "三张", "objective": "x", "cards": [
          {"position": "过去", "name": "card", "cn": "牌", "type": "Major", "reversed": false, "image": "a.png"}]}
        """#
        let oldCast = try JSONDecoder().decode(TarotCast.self, from: Data(old.utf8))
        XCTAssertNil(oldCast.cards[0].night)
        XCTAssertEqual(oldCast.readingMessage(question: "q"), "爸比，我抽了三张，帮我断断。问的是：q。 [塔罗#9]")
    }

    /// 122：night 缺字段、类型不对、是 null、整段不是对象，都不让整副牌解不出来
    func testNightDecodingIsTolerant() throws {
        func card(_ night: String) throws -> TarotCard {
            let json = #"{"position": "过去·身份", "name": "n", "cn": "愚者", "type": "major", "reversed": false, "image": "a.png""#
                + (night.isEmpty ? "" : ", \"night\": \(night)") + "}"
            return try JSONDecoder().decode(TarotCard.self, from: Data(json.utf8))
        }
        XCTAssertNil(try card("").night)
        XCTAssertNil(try card("null").night)
        let onlyColumn = try XCTUnwrap(try card(#"{"column": "play"}"#).night)
        XCTAssertEqual(onlyColumn.displayLabel, "玩法"); XCTAssertEqual(onlyColumn.summary, "")
        let wrongTypes = try XCTUnwrap(try card(#"{"column": 3, "label": null, "desc": ["x"], "interpret": "只有解读"}"#).night)
        XCTAssertEqual(wrongTypes.displayLabel, ""); XCTAssertEqual(wrongTypes.summary, "只有解读"); XCTAssertEqual(wrongTypes.more, "")
        XCTAssertEqual(try card(#"{"column": "emotion", "label": "", "desc": "d"}"#).night?.displayLabel, "关系")
        XCTAssertEqual(try card(#""不是对象""#).night?.summary, "")
        XCTAssertEqual(try card("[1, 2]").night?.summary, "")
    }

    /// 122：夜里那副是 22 张；张数或位置数不对都不收，别的牌阵还是 78 张
    func testNightDealValidationUses22CardDeck() throws {
        func deal(_ spread: String, _ size: Int, _ positions: [String]) throws -> TarotDeal {
            let body: [String: Any] = ["deal_id": "d", "deck_size": size, "spread": spread, "spread_name": "夜里", "positions": positions]
            return try JSONDecoder().decode(TarotDeal.self, from: JSONSerialization.data(withJSONObject: body))
        }
        let night = ["过去·身份", "现在·关系", "未来·玩法"]
        XCTAssertTrue(try deal("night", 22, night).isValid)
        XCTAssertFalse(try deal("night", 78, night).isValid)
        XCTAssertFalse(try deal("night", 22, ["过去·身份", "现在·关系"]).isValid)
        XCTAssertFalse(try deal("three", 22, ["过去", "现在", "未来"]).isValid)
        XCTAssertTrue(try deal("three", 78, ["过去", "现在", "未来"]).isValid)
        XCTAssertFalse(try deal("tower", 78, ["x"]).isValid)
        XCTAssertEqual(TarotSpread.all, ["one", "three", "celtic", "night"])
        XCTAssertEqual(TarotSpread.title("night"), "夜里")
        XCTAssertEqual(TarotSpread.deckSize("night"), 22); XCTAssertEqual(TarotSpread.deckSize("celtic"), 78)
        XCTAssertEqual(TarotSpread.positions("night"), night)
        XCTAssertFalse(TarotSpread.asksQuestion("night")); XCTAssertTrue(TarotSpread.asksQuestion("three"))
    }

    /// 122：22 张的那副，第 22 张以后不能选
    func testNightSelectionRejectsIndicesBeyond22() {
        var selection = TarotSelection(deckSize: 22, requiredCount: 3)
        for i in [22, 40, 77, -1] { selection.tap(i); selection.tap(i) }
        XCTAssertEqual(selection.picks, []); XCTAssertNil(selection.preview)
        for i in [0, 21, 10] { selection.tap(i); selection.tap(i) }
        XCTAssertEqual(selection.picks, [0, 21, 10]); XCTAssertTrue(selection.freeze())
    }

    /// 122：22 张的牌扇照样摊满半圆、不出屏幕，点在哪张认哪张：最上面那张、抬起那张、滑着一张张换都对
    func testNightFanOf22MatchesVisibleTopCard() {
        let deck = 22
        for width in [295.0, 353.0, 400.0] as [CGFloat] {
            let height = width * TarotTableStyle.stageHeight
            let halfWidth = Double(width * TarotTableStyle.fanCardWidth / 2)
            let halfLength = halfWidth / Double(TarotTableStyle.cardAspect)
            // 两头不出屏幕，最右一张就是半圆的尽头
            XCTAssertEqual(TarotFan.placement(deck - 1, width: width, height: height, lifted: false, deckSize: deck).angle, 2 * Double.pi, accuracy: 1e-9)
            for index in 0..<deck {
                for lifted in [false, true] {
                    let (center, angle) = TarotFan.placement(index, width: width, height: height, lifted: lifted, deckSize: deck)
                    let rotation = angle + Double.pi / 2
                    let extentX = abs(cos(rotation)) * halfWidth + abs(sin(rotation)) * halfLength
                    XCTAssertGreaterThanOrEqual(Double(center.x) - extentX, -1e-9)
                    XCTAssertLessThanOrEqual(Double(center.x) + extentX, Double(width) + 1e-9)
                }
                // 按在每张露出来那一条的中间（往右半张牌宽之内只有它自己），认出来就是它
                let (center, angle) = TarotFan.placement(index, width: width, height: height, lifted: false, deckSize: deck)
                let point = index == deck - 1 ? center
                    : CGPoint(x: center.x - CGFloat(sin(angle) * -halfWidth * 0.6), y: center.y + CGFloat(cos(angle) * -halfWidth * 0.6))
                XCTAssertEqual(TarotFan.card(at: point, width: width, height: height, picks: [], preview: nil, deckSize: deck), index,
                               "width \(width) index \(index)")
            }
            // 抬起的那张，第二下点在它身上哪儿都算它
            for lifted in 0..<deck {
                let (center, angle) = TarotFan.placement(lifted, width: width, height: height, lifted: true, deckSize: deck)
                for (u, v) in [(0.0, 0.0), (-0.9, 0.0), (0.9, 0.0), (0.0, 0.9), (0.0, -0.9), (0.9, -0.9), (-0.9, 0.9)] {
                    let across = u * halfWidth, along = v * halfLength
                    let point = CGPoint(x: center.x + CGFloat(along * cos(angle) - across * sin(angle)),
                                        y: center.y + CGFloat(along * sin(angle) + across * cos(angle)))
                    guard point.y >= height - width * TarotTableStyle.fanHitHeight else { continue }
                    XCTAssertEqual(TarotFan.card(at: point, width: width, height: height, picks: [], preview: lifted, deckSize: deck), lifted)
                }
            }
            // 左右滑一张一张往后换，滑得到最后一张（第 22 张），不会跳到 22 以外
            var last = -1
            for step in 0..<1000 {
                let angle = Double.pi + Double(step) / 999 * Double.pi
                let radius = Double(width * TarotTableStyle.fanRadius)
                let point = CGPoint(x: width / 2 + CGFloat(cos(angle) * radius),
                                    y: height - width * TarotTableStyle.fanBottom + CGFloat(sin(angle) * radius))
                guard let index = TarotFan.card(at: point, width: width, height: height, picks: [], preview: 8, liftAware: false, deckSize: deck) else { continue }
                XCTAssertGreaterThanOrEqual(index, last)
                if last >= 0 { XCTAssertLessThanOrEqual(index - last, 1) }
                last = index
            }
            XCTAssertEqual(last, deck - 1)
            // 放上桌的不算；按在空处是 nil；预览号超出这副牌也不当抬起
            let top = TarotFan.placement(deck - 1, width: width, height: height, lifted: false, deckSize: deck).center
            XCTAssertNotEqual(TarotFan.card(at: top, width: width, height: height, picks: [deck - 1], preview: nil, deckSize: deck), deck - 1)
            XCTAssertNil(TarotFan.card(at: CGPoint(x: width / 2, y: 4), width: width, height: height, picks: [], preview: nil, deckSize: deck))
            XCTAssertEqual(TarotFan.card(at: top, width: width, height: height, picks: [], preview: 60, deckSize: deck), deck - 1)
        }
        // 不传 deckSize 还是 78 张那套
        let width: CGFloat = 353, height = width * TarotTableStyle.stageHeight
        XCTAssertEqual(TarotFan.placement(77, width: width, height: height, lifted: false).angle, 2 * Double.pi, accuracy: 1e-9)
    }

    /// 10-31 转牌扇：半圆里一次摊 24 张，画在哪认在哪，转到外面的认不到
    func testTurnedFanFindsTheCardDrawnUnderTheFinger() {
        let width: CGFloat = 430, height: CGFloat = 400
        let visible = TarotFan.visible(deckSize: 78)
        XCTAssertEqual(visible, 24)
        XCTAssertEqual(TarotFan.maxShift(deckSize: 78), 54)
        for shift in [0.0, 10.5, 54.0] {
            for index in 0..<78 where TarotFan.onFan(index, deckSize: 78, visible: visible, shift: shift) {
                let (center, angle) = TarotFan.placement(index, width: width, height: height, lifted: false, deckSize: 78, visible: visible, shift: shift)
                // 按在这张露出来的那一条上（靠外的一端，后面的牌盖不到）
                let halfLength = Double(width * TarotTableStyle.fanCardWidth / TarotTableStyle.cardAspect / 2)
                let tip = CGPoint(x: center.x + CGFloat(cos(angle) * halfLength * 0.9), y: center.y + CGFloat(sin(angle) * halfLength * 0.9))
                let hit = TarotFan.card(at: tip, width: width, height: height, picks: [], preview: nil, deckSize: 78, visible: visible, shift: shift)
                XCTAssertNotNil(hit)
                XCTAssertLessThanOrEqual(abs((hit ?? -99) - index), 1, "shift \(shift) index \(index)")
            }
        }
        XCTAssertFalse(TarotFan.onFan(0, deckSize: 78, visible: visible, shift: 54))
        XCTAssertFalse(TarotFan.onFan(77, deckSize: 78, visible: visible, shift: 0))
        // 夜里 22 张一屏摊得下，不用转
        XCTAssertEqual(TarotFan.maxShift(deckSize: 22), 0)
    }
}
