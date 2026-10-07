import XCTest

final class MorandiAppearanceTests: XCTestCase {
    func testFiveDayPages() { Self.captureFiveDayPages(in: self) }

    static func captureFiveDayPages(in testCase: XCTestCase) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-ui-test-memory-review", "-app.skin", "day"]
        app.launch()
        XCTAssertTrue(app.buttons["我们"].waitForExistence(timeout: 15))
        capture("01-chat", in: testCase)
        for (label, name) in [("我们", "02-us"), ("玩", "03-play"), ("回忆", "04-memories"), ("抽屉", "05-drawer")] {
            app.descendants(matching: .any).matching(identifier: "root-tab-bar").firstMatch.buttons[label].tap()
            XCTAssertTrue(app.buttons["柯"].waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 2)
            capture(name, in: testCase)
            if label == "我们" { captureUsDetails(app, in: testCase) }
        }
    }

    private static func captureUsDetails(_ app: XCUIApplication, in testCase: XCTestCase) {
        let edit = app.buttons["us-shift-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        for _ in 0..<3 where !edit.isHittable { app.swipeUp() }
        edit.tap()
        XCTAssertTrue(app.staticTexts["班次小记"].waitForExistence(timeout: 5))
        capture("06-shift-journal", in: testCase)
        app.buttons["返回"].firstMatch.tap()
        let reminder = app.buttons["us-reminder-journal"]
        for _ in 0..<3 where !reminder.isHittable { app.swipeUp() }
        reminder.tap()
        XCTAssertTrue(app.staticTexts["今晚的惦记"].waitForExistence(timeout: 5))
        capture("07-reminder-journal", in: testCase)
        app.buttons["返回"].firstMatch.tap()
        let notebook = app.buttons["us-quote-notebook"]
        for _ in 0..<7 where !notebook.isHittable { app.swipeUp() }
        XCTAssertTrue(notebook.isHittable)
        capture("08-calendar-and-notebook", in: testCase)
        notebook.tap()
        XCTAssertTrue(app.navigationBars["小本子"].waitForExistence(timeout: 5))
        capture("09-notebook", in: testCase)
        app.buttons["返回"].firstMatch.tap()
    }

    private static func capture(_ name: String, in testCase: XCTestCase) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}
