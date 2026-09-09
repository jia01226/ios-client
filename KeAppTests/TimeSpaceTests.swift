import XCTest
import UIKit
@testable import KeApp

final class TimeSpaceTests: XCTestCase {
    @MainActor func testLegacyScrollProbeTracksOffsetAndStopsObserving() async {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        scroll.contentSize = CGSize(width: 300, height: 1600)
        let probe = TimeScrollProbe.ProbeView()
        var offsets: [CGFloat] = []
        probe.onScroll = { offsets.append($0) }
        scroll.addSubview(probe)
        probe.attach()
        scroll.contentOffset.y = 220
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(offsets.last, 220)
        probe.stop()
        scroll.contentOffset.y = 330
        await Task.yield()
        XCTAssertEqual(offsets.last, 220)
    }

    func testCalendarHandlesLeapMonthAndMondayGridAcrossYears() {
        let model = TimeCalendarModel()
        let leap = CompanionDate.parse("2024-02-01")!
        XCTAssertEqual(model.monthDays(leap).compactMap { $0 }.count, 29)
        let sunday = CompanionDate.parse("2026-02-01")!
        XCTAssertTrue(model.monthDays(sunday).prefix(6).allSatisfy { $0 == nil })
        XCTAssertEqual(model.movingMonth(CompanionDate.parse("2026-12-31")!, by: 1), CompanionDate.parse("2027-01-01")!)
        XCTAssertEqual(model.calendar.timeZone.identifier, "Asia/Shanghai")
    }

    func testMoonIsCenteredAndCalendarEndsInsideSameMoon() {
        let size = CGSize(width: 430, height: 830)
        let start = TimeMoonFraming.frame(size: size, bottomInset: 0, progress: 0)
        let end = TimeMoonFraming.frame(size: size, bottomInset: 0, progress: 1)
        XCTAssertEqual(start.center.x, end.center.x)
        XCTAssertEqual(start.center.y - start.diameter / 2, size.height - start.diameter * 0.2, accuracy: 0.1)
        XCTAssertGreaterThan(end.diameter / 2, hypot(size.width / 2, size.height / 2))
        XCTAssertEqual(TimeMoonFraming.layerTravel(progress: 1, depth: 0.8, reduceMotion: true), 0)
    }
}
