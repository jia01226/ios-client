import XCTest

final class CompanionInteractionTests: XCTestCase {
    func testCalendarPrivacyAndDailyPages() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-app.skin", "day"]
        app.launch()
        XCTAssertTrue(app.buttons["我们"].waitForExistence(timeout: 5))
        app.buttons["我们"].tap()
        XCTAssertFalse(app.buttons["play-diary"].exists)
        XCTAssertFalse(app.buttons["play-moments"].exists)
        app.buttons["玩"].tap()
        XCTAssertTrue(app.buttons["play-diary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["让柯开一局"].exists)
        XCTAssertFalse(app.buttons["抽一张牌"].exists)
        capture("play-home")
        app.buttons["play-diary"].tap()
        XCTAssertTrue(app.staticTexts["匿名日记"].waitForExistence(timeout: 5))
        let diarySearch = app.searchFields["查找标题、正文或作者"]
        XCTAssertTrue(diarySearch.waitForExistence(timeout: 3))
        diarySearch.tap()
        diarySearch.typeText("月光")
        XCTAssertTrue(app.staticTexts["枕边的一页"].waitForExistence(timeout: 3))
        capture("companion-diary")
        app.keyboards.buttons["Search"].tap()
        app.buttons["close"].tap()
        let closeDiary = app.buttons["companion-close"]
        XCTAssertTrue(closeDiary.waitForExistence(timeout: 3))
        closeDiary.tap()
        app.buttons["play-moments"].tap()
        XCTAssertTrue(app.staticTexts["今天的天空很好看。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["评论"].exists)
        capture("companion-moments")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
