import XCTest

final class MorandiAppearanceTests: XCTestCase {
    func testFiveDayPages() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-ui-test-memory-review", "-app.skin", "day"]
        app.launch()
        XCTAssertTrue(app.buttons["我们"].waitForExistence(timeout: 15))
        capture("01-chat")
        for (label, name) in [("我们", "02-us"), ("玩", "03-play"), ("回忆", "04-memories"), ("抽屉", "05-drawer")] {
            app.descendants(matching: .any).matching(identifier: "root-tab-bar").firstMatch.buttons[label].tap()
            XCTAssertTrue(app.buttons["柯"].waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 2)
            capture(name)
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
