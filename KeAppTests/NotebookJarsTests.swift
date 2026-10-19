import XCTest
@testable import KeApp

/// 121：荷包「花钱｜攒钱」——罐子的数据怎么认、额度条什么颜色、金额怎么发出去。
final class NotebookJarsTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testOverviewDecodesAndPutsFreeJarFirst() throws {
        let json = #"""
        {"total_cents": 317000, "jars": [
         {"id": 2, "title": "一起去海边", "kind": "goal", "target_cents": 300000, "saved_cents": 128000, "percent": 42, "reached": false, "deadline": "2026-12-31", "days_left": 73, "created_at": "2026-10-01 10:00:00", "updated_at": "2026-10-18 10:00:00"},
         {"id": 1, "title": "随手攒", "kind": "free", "target_cents": 0, "saved_cents": 64000, "percent": null, "reached": false, "deadline": "", "days_left": null, "created_at": "2026-10-01", "updated_at": "2026-10-01"},
         {"id": 3, "title": "新相机", "kind": "goal", "target_cents": 100000, "saved_cents": 125000, "percent": 125, "reached": true, "deadline": "", "days_left": null, "created_at": "x", "updated_at": "x"}
        ], "month_tip": {"month": "2026-10", "saved_cents": 132600}}
        """#
        let overview = try decoder.decode(JarOverview.self, from: Data(json.utf8))
        XCTAssertEqual(overview.ordered.map(\.id), [1, 2, 3])
        XCTAssertEqual(overview.month_tip?.saved_cents, 132600)
        XCTAssertEqual(JarText.monthName("2026-10"), "10月")
        let beach = overview.jars[0]
        XCTAssertEqual(beach.percentText, "42%")
        XCTAssertEqual(beach.fraction, 128000.0 / 300000, accuracy: 1e-9)
        XCTAssertEqual(overview.jars[2].fraction, 1, "攒够了就满条")
        XCTAssertTrue(overview.jars[1].isFree)
        XCTAssertNil(overview.jars[1].days_left)

        let sparse = try decoder.decode(JarOverview.self, from: Data(#"{"jars":[{"id":1,"title":"随手攒","kind":"free","saved_cents":500}],"month_tip":null}"#.utf8))
        XCTAssertEqual(sparse.total_cents, 500)
        XCTAssertNil(sparse.month_tip)
        XCTAssertEqual(sparse.jars[0].deadline, "")
    }

    func testEntriesNewestFirstAndWriteReplies() throws {
        let json = #"""
        {"jar": {"id": 2, "title": "一起去海边", "kind": "goal", "target_cents": 300000, "saved_cents": 128000, "percent": 42, "reached": false, "deadline": "", "days_left": null, "created_at": "a", "updated_at": "b"},
         "entries": [
          {"id": 5, "amount_cents": 20000, "actor": "佳佳", "note": "工资", "created_at": "2026-10-03 09:00:00", "edited_by": null, "updated_at": null},
          {"id": 9, "amount_cents": -5000, "actor": "柯", "note": "", "created_at": "2026-10-14 21:00:00", "edited_by": "佳佳", "updated_at": "2026-10-15 08:00:00"},
          {"id": 7, "amount_cents": 1050, "actor": "柯", "note": "零钱", "created_at": "2026-10-14 21:00:00", "edited_by": "", "updated_at": null}
         ]}
        """#
        let detail = try decoder.decode(JarDetail.self, from: Data(json.utf8))
        XCTAssertEqual(detail.entries.sorted(by: JarEntry.newestFirst).map(\.id), [9, 7, 5])
        XCTAssertEqual(JarText.actorName("柯"), "柯")
        XCTAssertEqual(JarText.actorName("佳佳"), "佳佳")
        XCTAssertEqual(JarText.yuanField(-5000), "50")
        XCTAssertEqual(JarText.yuanField(1050), "10.50")

        let bare = try decoder.decode(JarReply.self, from: Data(#"{"ok": true}"#.utf8))
        XCTAssertNil(bare.overview, "只回 ok 的要再拉一次总览")
        let full = try decoder.decode(JarReply.self, from: Data(#"{"ok": true, "total_cents": 0, "jars": [], "month_tip": null}"#.utf8))
        XCTAssertNotNil(full.overview)
    }

    func testGentleTextsAndAmountParsing() {
        XCTAssertEqual(JarText.daysLeft(73), "还有 73 天")
        XCTAssertEqual(JarText.daysLeft(0), "今天到期")
        XCTAssertEqual(JarText.daysLeft(-3), "过了 3 天")
        XCTAssertNil(JarText.daysLeft(nil))
        XCTAssertEqual(JarText.dayName("2026-12-31"), "12月31日")
        XCTAssertEqual(JarText.parseYuan("1,326.5"), 1326.5)
        XCTAssertEqual(JarText.parseYuan("¥200元"), 200)
        XCTAssertNil(JarText.parseYuan("0"))
        XCTAssertNil(JarText.parseYuan("-5"))
        XCTAssertNil(JarText.parseYuan("0.001"))
        XCTAssertNil(JarText.parseYuan("abc"))
    }

    func testQuotaToneThresholds() {
        let roomy = PurseQuota(cap: 300000, spent: 114000, left: 186000)
        XCTAssertEqual(roomy.leftPercent, 62)
        XCTAssertEqual(roomy.tone, .plenty)
        XCTAssertEqual(PurseQuota(cap: 100000, spent: 69000, left: nil).tone, .plenty)
        XCTAssertEqual(PurseQuota(cap: 100000, spent: 70000, left: nil).tone, .low)
        XCTAssertEqual(PurseQuota(cap: 100000, spent: 90000, left: nil).tone, .low)
        XCTAssertEqual(PurseQuota(cap: 100000, spent: 90100, left: nil).tone, .almostOut)
        let over = PurseQuota(cap: 100000, spent: 120000, left: -20000)
        XCTAssertTrue(over.over)
        XCTAssertEqual(over.tone, .over)
        XCTAssertEqual(over.leftRatio, 0)
        XCTAssertEqual(PurseQuota.resetDay(month: "2026-10"), "11月1日")
        XCTAssertEqual(PurseQuota.resetDay(month: "2026-12"), "1月1日")
    }

    func testYuanGoesOutAsExactDecimalAndServerReasonSurfaces() throws {
        let body = try JSONSerialization.data(withJSONObject: ["amount": APIClient.yuanValue(12.3), "target": APIClient.yuanValue(3000)], options: [.sortedKeys])
        XCTAssertEqual(String(data: body, encoding: .utf8), #"{"amount":12.3,"target":3000}"#)
        XCTAssertEqual(JarStore.reason(APIError.badStatus(400, "罐子里没有这么多")), "罐子里没有这么多")
        XCTAssertEqual(JarStore.reason(APIError.badStatus(500, "")), "没接上，再试一次。")
        XCTAssertEqual(JarStore.reason(URLError(.timedOut)), "没接上，再试一次。")
    }
}
