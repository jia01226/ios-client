import XCTest

final class CompanionInteractionTests: XCTestCase {
    func testCoReadingSearchAndJoin() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-companion", "-ui-test-coreading", "-app.skin", "day"]
        app.launch()
        XCTAssertTrue(app.buttons["玩"].waitForExistence(timeout: 5))
        app.buttons["玩"].tap()
        XCTAssertTrue(app.buttons["play-reading"].waitForExistence(timeout: 5))
        app.buttons["play-reading"].tap()
        let field = app.textFields["coreading-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("小王子")
        app.buttons["coreading-search"].tap()
        XCTAssertTrue(app.buttons["coreading-join"].waitForExistence(timeout: 8))
        app.buttons["coreading-join"].tap()
        XCTAssertTrue(app.buttons["coreading-ask-ke"].waitForExistence(timeout: 5))
        capture("coreading-reading-page")
    }

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
        capture("diary-paper-list")
        app.buttons["diary-row-2"].tap()
        XCTAssertTrue(app.buttons["下一篇"].waitForExistence(timeout: 3))
        capture("diary-paper-reader")
        app.buttons["下一篇"].tap()
        XCTAssertTrue(app.staticTexts["晚风"].waitForExistence(timeout: 3))
        app.buttons["下一篇"].tap()
        XCTAssertTrue(app.staticTexts["这一页还锁着，可以在聊天里问柯。"].waitForExistence(timeout: 3))
        app.buttons["日记菜单"].tap()
        XCTAssertFalse(app.buttons["写评论"].exists)
        app.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["diary-search-toggle"].tap()
        let diarySearch = app.textFields["diary-search-field"]
        XCTAssertTrue(diarySearch.waitForExistence(timeout: 3))
        diarySearch.tap()
        diarySearch.typeText("月光")
        XCTAssertTrue(app.staticTexts["枕边的一页"].waitForExistence(timeout: 3))
        capture("companion-diary")
        app.buttons["取消"].tap()
        let closeDiary = app.buttons["companion-close"]
        XCTAssertTrue(closeDiary.waitForExistence(timeout: 3))
        closeDiary.tap()
        app.buttons["play-moments"].tap()
        XCTAssertTrue(app.staticTexts["今天的天空很好看。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["评论"].exists)
        capture("companion-moments")
    }
    func testDiaryAuthorsAndAccessibleReading() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-app.skin", "night"]
        app.launch()
        app.buttons["玩"].tap()
        app.buttons["play-diary"].tap()
        XCTAssertTrue(app.buttons["diary-row-1"].waitForExistence(timeout: 5))
        app.buttons["diary-filter-我"].tap()
        XCTAssertTrue(app.buttons["diary-row-1"].exists)
        XCTAssertFalse(app.buttons["diary-row-2"].exists)
        app.buttons["diary-filter-柯"].tap()
        XCTAssertFalse(app.buttons["diary-row-1"].exists)
        XCTAssertTrue(app.buttons["diary-row-2"].exists)
        capture("diary-paper-night-list")
        app.buttons["diary-row-2"].tap()
        capture("diary-paper-night-reader")
        app.terminate()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-app.skin", "day", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["玩"].tap()
        app.buttons["play-diary"].tap()
        XCTAssertTrue(app.buttons["diary-row-1"].waitForExistence(timeout: 5))
        capture("diary-paper-large-list")
        app.buttons["diary-row-1"].tap()
        XCTAssertTrue(app.buttons["下一篇"].waitForExistence(timeout: 3))
        capture("diary-paper-large-reader")
    }

    func testDiaryReaderDeletionFailureShowsRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-ui-test-diary-failure", "-app.skin", "day"]
        app.launch()
        app.buttons["玩"].tap()
        app.buttons["play-diary"].tap()
        XCTAssertTrue(app.buttons["diary-row-2"].waitForExistence(timeout: 5))
        app.buttons["diary-row-2"].tap()
        app.buttons["日记菜单"].tap()
        app.buttons["写评论"].tap()
        XCTAssertTrue(app.navigationBars["写评论"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
        app.buttons["日记菜单"].tap()
        app.buttons["删除"].tap()
        app.alerts.buttons["删除"].tap()
        XCTAssertTrue(app.buttons["重试"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["下一篇"].exists)
        app.buttons["重试"].tap()
        XCTAssertTrue(app.buttons["重试"].waitForExistence(timeout: 5))
        capture("diary-paper-error-reader")
    }

    func testDiaryAuthorFindsOlderPages() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-ui-test-diary-paging", "-app.skin", "day"]
        app.launch()
        app.buttons["玩"].tap()
        app.buttons["play-diary"].tap()
        XCTAssertTrue(app.buttons["diary-filter-我"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["diary-row-1"].exists)
        app.buttons["diary-filter-我"].tap()
        XCTAssertTrue(app.buttons["diary-row-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["diary-row-100"].exists)
    }

    func testTarotDrawShowsCardsAndHandsToKe() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-app.skin", "day"]
        app.launch()
        XCTAssertTrue(app.buttons["玩"].waitForExistence(timeout: 5))
        app.buttons["玩"].tap()
        XCTAssertTrue(app.buttons["play-tarot"].waitForExistence(timeout: 5))
        capture("tarot-play-entry")
        app.buttons["play-tarot"].tap()
        XCTAssertTrue(app.buttons["tarot-draw"].waitForExistence(timeout: 5))
        let question = app.textFields["问题"].firstMatch.exists ? app.textFields["问题"].firstMatch : app.textViews.firstMatch
        question.tap()
        question.typeText("他今晚会不会来找我")
        app.buttons["三张"].tap()
        capture("tarot-before-draw")
        app.buttons["tarot-draw"].tap()
        // 洗牌→发牌→翻牌的仪式动画比原来长，放宽等待。
        XCTAssertTrue(app.buttons["tarot-ask-ke"].waitForExistence(timeout: 25))
        sleep(2)
        capture("tarot-cards")
        app.buttons["tarot-ask-ke"].tap()
        XCTAssertTrue(app.buttons["柯"].waitForExistence(timeout: 5))
        sleep(2)
        capture("tarot-handoff-chat")
    }

    func testGardenEntryHandsToKe() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-app.skin", "day"]
        app.launch()
        XCTAssertTrue(app.buttons["玩"].waitForExistence(timeout: 5))
        app.buttons["玩"].tap()
        XCTAssertTrue(app.buttons["play-garden"].waitForExistence(timeout: 5))
        app.buttons["play-garden"].tap()
        XCTAssertTrue(app.buttons["garden-ask-ke"].waitForExistence(timeout: 5))
        capture("garden-entry")
        app.buttons["garden-ask-ke"].tap()
        XCTAssertTrue(app.buttons["柯"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "去花园看看")).firstMatch.waitForExistence(timeout: 8))
        capture("garden-handoff-chat")
    }

    func testFortuneRunsAndHandsToKe() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-companion", "-app.skin", "day"]
        app.launch()
        XCTAssertTrue(app.buttons["玩"].waitForExistence(timeout: 5))
        app.buttons["玩"].tap()
        XCTAssertTrue(app.buttons["play-fortune"].waitForExistence(timeout: 5))
        app.buttons["play-fortune"].tap()
        XCTAssertTrue(app.buttons["fortune-run"].waitForExistence(timeout: 5))
        capture("fortune-form")
        app.buttons["fortune-run"].tap()
        XCTAssertTrue(app.buttons["fortune-ask-ke"].waitForExistence(timeout: 15))
        app.buttons["fortune-ask-ke"].tap()
        XCTAssertTrue(app.buttons["柯"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "帮我看看")).firstMatch.waitForExistence(timeout: 8))
        capture("fortune-handoff-chat")
    }

    func testTarotCardMessageOpensEachCard() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-tarot-cards", "-ui-test-companion", "-app.skin", "day"]
        app.launch()
        let first = app.buttons["打开图片 月亮·逆位"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        sleep(3)
        capture("tarot-card-message")
        first.tap()
        sleep(2)
        capture("tarot-card-first-open")
        XCTAssertTrue(app.buttons["关闭"].waitForExistence(timeout: 5) || app.buttons["关闭图片"].waitForExistence(timeout: 1), "第一张牌没打开")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
