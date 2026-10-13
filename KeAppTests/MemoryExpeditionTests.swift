#if DEBUG
import XCTest
@testable import KeApp

final class MemoryExpeditionTests: XCTestCase {
    private func rows() throws -> [MemoryFlower] {
        try (0..<647).map { i in
            let row: [String: Any] = ["id": "\(i)", "title": "匿名", "body": "匿名",
                "author": "ke", "state": "bloom", "recall_count": 647-i,
                "last_recalled_at": i < 9 ? "2026-10-12" : "2026-09-01"]
            return try JSONDecoder().decode(MemoryFlower.self, from: JSONSerialization.data(withJSONObject: row))
        }
    }
    func testAll647IDsAppearOnceInBoundedGlades() throws {
        let rows = try rows()
        let pages = MemoryExpeditionRoute.pages(rows + [rows[0]])
        XCTAssertEqual(pages.flatMap { $0 }.count, 647)
        XCTAssertEqual(Set(pages.flatMap { $0 }.map(\.id)).count, 647)
        XCTAssertTrue(pages.allSatisfy { $0.count <= 9 })
        XCTAssertEqual(pages[0].map(\.id), (0..<9).map(String.init))
        XCTAssertEqual(pages.map { $0.map(\.id) }, MemoryExpeditionRoute.pages(rows.reversed()).map { $0.map(\.id) })
    }
    func testFlowerStyleAndRotationStayStable() throws {
        for row in try rows() {
            XCTAssertEqual(MemoryExpeditionRoute.sprite(row), MemoryExpeditionRoute.sprite(row))
            XCTAssertTrue((-25...25).contains(MemoryExpeditionRoute.angle(row.id)))
        }
        XCTAssertTrue(MemoryExpeditionRoute.pages([]).isEmpty)
    }
    func testAllNineStylesExistAndStateOwnsBudSelection() throws {
        let flowers = try rows()
        let blooms = Set(flowers.map(MemoryExpeditionRoute.sprite))
        XCTAssertEqual(blooms, Set(MemoryExpeditionRoute.bloomSprites))
        var buds = Set<String>()
        for index in 0..<20 {
            let json: [String: Any] = ["id": "bud-\(index)", "state": "bud", "author": "ke", "title": "匿名", "body": "匿名"]
            let flower = try JSONDecoder().decode(MemoryFlower.self, from: JSONSerialization.data(withJSONObject: json))
            buds.insert(MemoryExpeditionRoute.sprite(flower))
        }
        XCTAssertEqual(buds, ["ExpeditionBud", "ExpeditionBudTight"])
        for asset in blooms.union(buds).union(["ExpeditionButterflySpirit"]) {
            XCTAssertNotNil(UIImage(named: asset), "Missing asset: \(asset)")
        }
    }
    func testSpiritLandingAndTrailAreFinite() {
        let start = CGPoint(x: 20, y: 90), end = CGPoint(x: 80, y: 35)
        XCTAssertEqual(SpiritFlightMotion.point(phase: 0, start: start, end: end), start)
        XCTAssertEqual(SpiritFlightMotion.point(phase: 1.25, start: start, end: end).x, end.x, accuracy: 0.0001)
        XCTAssertEqual(SpiritFlightMotion.point(phase: 1.25, start: start, end: end).y, end.y, accuracy: 0.0001)
        XCTAssertEqual(SpiritFlightMotion.trailOpacity(phase: 0), 0)
        XCTAssertEqual(SpiritFlightMotion.trailOpacity(phase: 1.25), 0)
        XCTAssertGreaterThan(SpiritFlightMotion.trailOpacity(phase: 0.5), 0)
    }
}
#endif
