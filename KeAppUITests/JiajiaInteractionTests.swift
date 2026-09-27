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
        let editButton = app.buttons["jiajia-edit-notes"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        XCTAssertTrue(editButton.isHittable)
        editButton.tap()
        let editor = app.textViews["jiajia-notes-editor"]
        if !editor.waitForExistence(timeout: 3) {
            // iOS 17 的 TabView 刚切页时，第一次合成点击偶尔会落在转场尾帧。
            // 只有编辑器确实没出现时再点一次，仍然验证真实弹层与取消语义。
            editButton.tap()
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(" Unsaved draft")
        app.buttons["取消"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 2))
        XCTAssertEqual(notes.label, original)
        XCTAssertTrue(app.buttons["柯"].isHittable)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }
}
