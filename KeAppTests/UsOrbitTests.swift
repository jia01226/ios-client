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

    func testCalendarCanRenderAdjacentMonths() throws {
        let viewModel = UsViewModel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let january = try XCTUnwrap(formatter.date(from: "2026-01-12"))
        let february = viewModel.month(byAdding: 1, to: january)

        XCTAssertEqual(viewModel.monthTitle(for: january), "2026年 1月")
        XCTAssertEqual(viewModel.monthTitle(for: february), "2026年 2月")
        XCTAssertEqual(viewModel.monthCells(for: january).compactMap { $0 }.count, 31)
        XCTAssertEqual(viewModel.monthCells(for: february).compactMap { $0 }.count, 28)
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
