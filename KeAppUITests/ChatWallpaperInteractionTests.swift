import XCTest

final class ChatWallpaperInteractionTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private static func openAppearance(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["打开聊天设置"].waitForExistence(timeout: 10))
        app.buttons["打开聊天设置"].tap()
        let entry = app.buttons["界面与气泡"]
        for _ in 0..<6 where !entry.isHittable { app.scrollViews.firstMatch.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.switches["chat-lockscreen-glass"].waitForExistence(timeout: 5))
    }

    private static func snapshot(_ app: XCUIApplication, _ name: String, in testCase: XCTestCase) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    func testCropPreviewLivePreferencesAndRelaunch() {
        Self.verify(in: self)
    }

    static func verify(in testCase: XCTestCase) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-wallpaper"]
        app.launch()
        openAppearance(app)
        let blur = app.sliders["chat-background-blur"]
        if !blur.isHittable { app.scrollViews.firstMatch.swipeUp() }
        blur.adjust(toNormalizedSliderPosition: 0.6)
        let dim = app.sliders["chat-background-dim"]
        if !dim.isHittable { app.scrollViews.firstMatch.swipeUp() }
        dim.adjust(toNormalizedSliderPosition: 0.5)
        let blurValue = blur.value as? String
        let dimValue = dim.value as? String
        snapshot(app, "wallpaper-live-half-panel", in: testCase)
        app.terminate()
        app.launch()
        openAppearance(app)
        let reloadedBlur = app.sliders["chat-background-blur"]
        if !reloadedBlur.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertEqual(reloadedBlur.value as? String, blurValue)
        let reloadedDim = app.sliders["chat-background-dim"]
        if !reloadedDim.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertEqual(reloadedDim.value as? String, dimValue)
        app.scrollViews.firstMatch.swipeDown()
        let crop = app.buttons["chat-background-crop"]
        if !crop.isHittable { app.scrollViews.firstMatch.swipeDown() }
        crop.tap()
        let preview = app.descendants(matching: .any).matching(identifier: "chat-wallpaper-crop-preview").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.pinch(withScale: 1.5, velocity: 1)
        preview.swipeLeft()
        snapshot(app, "wallpaper-crop", in: testCase)
        app.buttons["chat-wallpaper-save"].tap()
        XCTAssertTrue(app.switches["chat-lockscreen-glass"].waitForExistence(timeout: 5))
        app.buttons["返回聊天设置"].tap()
        app.buttons["关闭聊天设置"].tap()
        let input = app.textFields["chat-composer"]
        input.tap()
        input.typeText("preview")
        snapshot(app, "wallpaper-white-composer-keyboard", in: testCase)
        XCTAssertTrue(app.staticTexts["这是最新一条回复。"].exists)
        app.terminate()
        app.launchArguments += ["-app.skin", "night", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.textFields["chat-composer"].waitForExistence(timeout: 10))
        snapshot(app, "wallpaper-night-large-text", in: testCase)
        // Restore the appearance before the existing regression flows continue.
        openAppearance(app)
        let glass = app.switches["chat-lockscreen-glass"]
        if !glass.isHittable { app.scrollViews.firstMatch.swipeUp() }
        if glass.value as? String == "1" { glass.tap() }
        app.scrollViews.firstMatch.swipeDown()
        app.segmentedControls["chat-background-kind"].buttons["纯色"].tap()
        app.terminate()
    }
}
