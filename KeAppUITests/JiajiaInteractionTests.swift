import XCTest

final class JiajiaInteractionTests: XCTestCase {
    func testNotesEditorCancellationPreservesSavedContent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control"]
        app.launch()
        let tab = app.buttons["佳佳"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
        let notes = app.staticTexts["jiajia-notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 2))
        let original = notes.label
        app.buttons["jiajia-edit-notes"].tap()
        let editor = app.textViews["jiajia-notes-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        editor.tap()
        editor.typeText(" Unsaved draft")
        app.buttons["取消"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 2))
        XCTAssertEqual(notes.label, original)
        XCTAssertTrue(app.buttons["柯"].isHittable)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }
}
