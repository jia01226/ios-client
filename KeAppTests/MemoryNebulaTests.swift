import XCTest
@testable import KeApp

final class MemoryNebulaTests: XCTestCase {
    private func flower(_ json: String) throws -> MemoryFlower {
        try JSONDecoder().decode(MemoryFlower.self, from: Data(json.utf8))
    }

    func testGroupAndChangeAreDecodedAndOldServerFallsBackByCategory() throws {
        let grouped = try flower(#"{"id":"a","title":"t","body":"b","state":"bloom","author":"ke","category":"生活","group":"说好的","changed":"以前……，现在……"}"#)
        XCTAssertEqual(NebulaGroup.groupName(for: grouped), "说好的")
        XCTAssertEqual(grouped.changed, "以前……，现在……")
        let old = try flower(#"{"id":"b","title":"t","body":"b","state":"bloom","author":"other","category":"医疗"}"#)
        XCTAssertNil(old.group)
        XCTAssertEqual(NebulaGroup.groupName(for: old), "身体和药")
    }

    func testSixGroupsWithPromisesInTheMiddle() {
        XCTAssertEqual(NebulaGroup.all.map(\.name), ["日常吃喝", "身体和药", "以后的家", "亲密时刻", "难过的夜里", "说好的", "关于她"])
        XCTAssertEqual(NebulaGroup.named("说好的")?.kind, .whirlpool)
    }

    func testSeatDependsOnlyOnTheMemoryAndSitsInsideTheNebula() {
        let art = NebulaArt.art(.orion)
        let a = art.seat(for: "memory-1", thickness: 0.34), again = art.seat(for: "memory-1", thickness: 0.34)
        XCTAssertEqual(a, again)
        for i in 0..<50 {
            let s = art.seat(for: "m\(i)", thickness: 0.34)
            XCTAssertLessThanOrEqual(abs(s.x), 1); XCTAssertLessThanOrEqual(abs(s.y), 1)
            XCTAssertLessThan(abs(s.z), 0.6)
        }
        XCTAssertFalse(art.dust.joined().isEmpty)
    }

    func testTextureAndStarsUseTheSameProjection() {
        for cam in [NebulaCamera.home, NebulaCamera(yaw: 0.9, pitch: -0.4, zoom: 2, pan: CGSize(width: 12, height: -30)),
                    NebulaCamera(yaw: 3.3, pitch: 2.2, zoom: 0.8)] {
            let pr = NebulaProjection(camera: cam, size: CGSize(width: 390, height: 844), spin: 0.7, origin: SIMD2(0.1, -0.05))
            for (u, v) in [(0.0, 0.0), (0.5, -0.3), (-0.8, 0.9)] {
                let star = pr.project(SIMD3(u, v, 0)).0
                let tex = CGPoint(x: u, y: v).applying(pr.planeTransform)
                XCTAssertEqual(star.x, tex.x, accuracy: 0.001)
                XCTAssertEqual(star.y, tex.y, accuracy: 0.001)
            }
        }
    }

    func testRotationGoesAllTheWayRound() {
        let m = NebulaMotion(), size = CGSize(width: 390, height: 844)
        m.drag(.zero, size: size); m.drag(CGSize(width: 800, height: -800), size: size); m.endGesture(size: size)
        let c = m.camera(at: Date())
        XCTAssertGreaterThan(abs(c.yaw), 2 * .pi)
        XCTAssertGreaterThan(abs(c.pitch), 2 * .pi)
    }

    func testZoomedInDragMovesInsteadOfTurningAndStaysOnScreen() {
        let m = NebulaMotion(), size = CGSize(width: 390, height: 844)
        m.jump(NebulaCamera(zoom: 2))
        m.drag(.zero, size: size); m.drag(CGSize(width: 60, height: -40), size: size); m.endGesture(size: size)
        var c = m.camera(at: Date())
        XCTAssertEqual(c.yaw, 0); XCTAssertEqual(c.pan.width, 60, accuracy: 0.01); XCTAssertEqual(c.pan.height, -40, accuracy: 0.01)
        m.drag(.zero, size: size); m.drag(CGSize(width: 9000, height: 0), size: size); m.endGesture(size: size)
        c = m.camera(at: Date())
        XCTAssertLessThanOrEqual(c.pan.width, NebulaProjection.baseScale(size) * 2 * 0.95 + 0.01)
    }

    func testNebulaSitsBetweenHeaderAndButtons() {
        let size = CGSize(width: 390, height: 844), art = NebulaArt.art(.orion)
        let pr = NebulaProjection(camera: .home, size: size, spin: 0, origin: art.centroid)
        let c = pr.project(SIMD3(art.centroid.x, art.centroid.y, 0)).0
        XCTAssertEqual(c.x, 195, accuracy: 0.5)
        XCTAssertEqual(c.y, (NebulaProjection.topBand + size.height - NebulaProjection.bottomBand) / 2, accuracy: 0.5)
    }
}
