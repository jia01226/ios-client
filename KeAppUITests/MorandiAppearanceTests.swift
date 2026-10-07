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
        }
    }

    private static func capture(_ name: String, in testCase: XCTestCase) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}
