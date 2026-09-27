import XCTest
@testable import KeApp

@MainActor
final class UsOrbitTests: XCTestCase {
    func testRelationshipEventsAreAccumulatingAndBirthdaysAreCountdowns() {
        let viewModel = UsViewModel()

        XCTAssertEqual(viewModel.anniversaries.map(\.id), ["mine", "confession", "together", "ke"])
        XCTAssertEqual(viewModel.anniversaries[1].title, "表白的日子")
        XCTAssertFalse(viewModel.anniversaries[1].isYearly)
        XCTAssertFalse(viewModel.anniversaries[2].isYearly)
        XCTAssertTrue(viewModel.anniversaries[0].isYearly)
        XCTAssertTrue(viewModel.anniversaries[3].isYearly)
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

    func testWritingAndClearingShiftPersists() throws {
        let suiteName = "UsOrbitTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let date = Calendar.current.startOfDay(for: .now)
        let viewModel = UsViewModel(defaults: defaults)
        let note = "培训后去总院帮忙整理月底排班资料"
        viewModel.setShift(.other, note: note, on: date)
        XCTAssertEqual(viewModel.shift(on: date), .other)
        XCTAssertEqual(viewModel.shiftNote(on: date), note)
        XCTAssertEqual(UsViewModel(defaults: defaults).shift(on: date), .other)
        XCTAssertEqual(UsViewModel(defaults: defaults).shiftNote(on: date), note)

        viewModel.setShift(nil, on: date)
        XCTAssertNil(viewModel.shift(on: date))
        XCTAssertNil(UsViewModel(defaults: defaults).shift(on: date))
    }
}
