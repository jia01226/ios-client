import XCTest
@testable import KeApp

@MainActor
final class UsOrbitTests: XCTestCase {
    func testNoInventedRecordsBeforeFirstServerResponse() {
        let viewModel = UsViewModel()
        XCTAssertTrue(viewModel.anniversaries.isEmpty)
        XCTAssertTrue(viewModel.reminders.isEmpty)
        XCTAssertTrue(viewModel.thisWeek.isEmpty)
    }

    func testOrbitLeavesMissingNeighborSlotsEmptyAtBothEnds() {
        XCTAssertEqual(
            OrbitSelectionMath.visibleIndices(count: 3, position: 0),
            [0, 1]
        )
        XCTAssertEqual(
            OrbitSelectionMath.visibleIndices(count: 3, position: 1),
            [0, 1, 2]
        )
        XCTAssertEqual(
            OrbitSelectionMath.visibleIndices(count: 3, position: 2),
            [1, 2]
        )
    }

    func testProjectedSelectionDoesNotWrapPastOrbitEnds() {
        XCTAssertEqual(OrbitSelectionMath.nearestIndex(position: -2, count: 3), 0)
        XCTAssertEqual(OrbitSelectionMath.nearestIndex(position: 9, count: 3), 2)
        XCTAssertEqual(OrbitSelectionMath.nearestIndex(position: 0, count: 0), 0)
    }
}
