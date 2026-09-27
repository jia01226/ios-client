import XCTest

final class RootTabBarTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCustomNavigationHasNoSystemTabBarAcrossTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control"]
        app.launch()

        let customBar = app.descendants(matching: .any)
            .matching(identifier: "root-tab-bar").firstMatch
        XCTAssertTrue(customBar.waitForExistence(timeout: 5))

        for destination in ["柯", "我们", "玩", "回忆", "佳佳", "柯"] {
            customBar.buttons[destination].tap()
            XCTAssertTrue(customBar.isHittable)
            let systemBar = app.tabBars.firstMatch
            let disappeared = systemBar.waitForNonExistence(timeout: 2)
            XCTAssertTrue(
                disappeared || !systemBar.isHittable,
                "\(destination)页只能显示自定义导航，不能出现可操作的系统标签栏"
            )
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "navigation-\(destination)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
