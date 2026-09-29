import XCTest
@testable import KeApp

@MainActor
final class UsReminderTests: XCTestCase {
    func testRemoteScheduleMapsIntoVisibleReminders() {
        let rows = [
            RemoteReminder(
                id: 7,
                text: "下午三点吃药",
                scheduled_for: "2026-09-29 15:00:00",
                status: "pending",
                outcome: "",
                outcome_label: "",
                due: false
            )
        ]

        let reminders = UsViewModel.reminders(from: rows)

        XCTAssertEqual(reminders.map(\.id), ["7"])
        XCTAssertEqual(reminders.first?.text, "下午三点吃药")
        XCTAssertEqual(reminders.first?.dismissedByKe, false)
        XCTAssertNotNil(reminders.first?.dueAt)
    }

    func testFinishedScheduleDoesNotStayActive() {
        let rows = [
            RemoteReminder(
                id: 8,
                text: "已经完成",
                scheduled_for: "2026-09-29 09:00:00",
                status: "done",
                outcome: "resolved",
                outcome_label: "收好了",
                due: false
            )
        ]

        XCTAssertTrue(UsViewModel.reminders(from: rows).first?.dismissedByKe == true)
    }
}
