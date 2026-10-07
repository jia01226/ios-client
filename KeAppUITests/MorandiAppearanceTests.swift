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
            if label == "玩" { captureHut(app, in: testCase) }
        }
        app.terminate()
    }

    private static func captureUsDetails(_ app: XCUIApplication, in testCase: XCTestCase) {
        XCTAssertTrue(app.buttons["period-start"].isHittable)
        XCTAssertTrue(app.buttons["period-end"].isHittable)
        capture("14-calendar-first-screen", in: testCase)
        app.buttons["calendar-section-周班表"].tap()
        verifyQuickCancellation(app, in: testCase)
        let edit = app.buttons["us-shift-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        for _ in 0..<3 where !edit.isHittable { app.swipeUp() }
        edit.tap()
        XCTAssertTrue(app.staticTexts["班次小记"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shift-0-start"].label.contains("08:30"))
        XCTAssertTrue(app.buttons["shift-0-end"].label.contains("12:00"))
        XCTAssertTrue(app.buttons["shift-1-start"].label.contains("14:00"))
        XCTAssertTrue(app.buttons["shift-1-end"].label.contains("17:30"))
        capture("13-normal-shift", in: testCase)
        app.buttons["shift-mode-continuous"].tap()
        capture("06-shift-journal", in: testCase)
        app.buttons["shift-mode-split"].tap()
        XCTAssertTrue(app.buttons["shift-1-end"].waitForExistence(timeout: 5))
        app.buttons["shift-1-end"].tap()
        XCTAssertTrue(app.buttons["记好了"].waitForExistence(timeout: 5))
        capture("11-shift-time-picker", in: testCase)
        app.buttons["记好了"].tap()
        capture("10-split-shift", in: testCase)
        verifyCustomTemplate(app, in: testCase)
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

    private static func verifyQuickCancellation(_ app: XCUIApplication, in testCase: XCTestCase) {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let key = formatter.string(from: Date())
        let weekDay = app.buttons["week-day-" + key]
        XCTAssertTrue(weekDay.waitForExistence(timeout: 5))
        if !weekDay.label.contains("未排班") { weekDay.tap() }
        func assign() {
            weekDay.tap()
            XCTAssertTrue(app.staticTexts["写班表"].waitForExistence(timeout: 5))
            app.buttons["正常班"].tap()
            app.buttons["保存班表"].tap()
            let assigned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "正常班"), object: weekDay)
            XCTAssertEqual(XCTWaiter.wait(for: [assigned], timeout: 5), .completed)
        }
        assign()
        weekDay.tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "未排班"), object: weekDay)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed)
        XCTAssertFalse(app.staticTexts["写班表"].exists)
        assign()
        app.buttons["calendar-section-月历"].tap()
        let monthDay = app.buttons["calendar-day-" + key]
        for _ in 0..<7 where !monthDay.isHittable { app.swipeUp() }
        XCTAssertTrue(monthDay.isHittable)
        monthDay.tap()
        let monthCleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "未排班"), object: monthDay)
        XCTAssertEqual(XCTWaiter.wait(for: [monthCleared], timeout: 5), .completed)
        XCTAssertFalse(app.staticTexts["写班表"].exists)
        capture("12-one-tap-cancel", in: testCase)
        for _ in 0..<7 where !app.buttons["calendar-section-周班表"].isHittable { app.swipeDown() }
        app.buttons["calendar-section-周班表"].tap()
    }

    private static func verifyCustomTemplate(_ app: XCUIApplication, in testCase: XCTestCase) {
        app.buttons["shift-profile-kind"].tap()
        app.buttons["新建班次"].tap()
        let name = app.textFields["shift-template-name"]
        name.tap(); name.typeText("小夜班\n")
        let save = app.buttons["shift-profile-save"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["这个班次记好了"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !app.buttons["返回"].firstMatch.isHittable { app.swipeDown() }
        capture("15-custom-shift", in: testCase)
    }

    private static func captureHut(_ app: XCUIApplication, in testCase: XCTestCase) {
        XCTAssertFalse(app.buttons["play-moments"].exists)
        XCTAssertTrue(app.buttons["play-hut"].waitForExistence(timeout: 5))
        app.buttons["play-hut"].tap()
        XCTAssertTrue(app.staticTexts["柯的山屋"].waitForExistence(timeout: 5))
        capture("20-hut-room", in: testCase)
        for (key, title) in [("map", "地图"), ("cairn", "石堆"), ("polaroids", "拍立得"), ("facts", "事实簿"), ("floe", "浮冰"), ("photos", "墙上的照片"), ("weather", "窗外"), ("letters", "小锁信")] {
            app.buttons["hut-" + key].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            if key == "facts" { app.buttons["小习惯 · 1"].tap() }
            if key == "letters" {
                let field = app.textViews["hut-letter-text"]
                XCTAssertTrue(field.waitForExistence(timeout: 5))
                field.tap(); field.typeText("这是一封模拟器测试信。")
                app.buttons["hut-letter-send"].tap()
                XCTAssertTrue(app.staticTexts["信放好了，等柯看。"].waitForExistence(timeout: 5))
            }
            capture("21-hut-" + key, in: testCase)
            app.buttons["hut-object-close"].tap()
        }
        app.buttons["hut-close"].tap()
    }

    private static func capture(_ name: String, in testCase: XCTestCase) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}
