import XCTest

final class ChatWallpaperInteractionTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func openAppearance(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["打开聊天设置"].waitForExistence(timeout: 10))
        app.buttons["打开聊天设置"].tap()
        let entry = app.buttons["界面与气泡"]
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.switches["chat-lockscreen-glass"].waitForExistence(timeout: 5))
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCropPreviewLivePreferencesAndRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-scroll-control", "-ui-test-wallpaper"]
        app.launch()
        openAppearance(app)
        let blur = app.sliders["chat-background-blur"]
        if !blur.isHittable { app.swipeUp() }
        blur.adjust(toNormalizedSliderPosition: 0.6)
        let dim = app.sliders["chat-background-dim"]
        if !dim.isHittable { app.swipeUp() }
        dim.adjust(toNormalizedSliderPosition: 0.5)
        let blurValue = blur.value as? String
        let dimValue = dim.value as? String
        snapshot(app, "wallpaper-live-half-panel")
        app.terminate()
        app.launch()
        openAppearance(app)
        let reloadedBlur = app.sliders["chat-background-blur"]
        if !reloadedBlur.isHittable { app.swipeUp() }
        XCTAssertEqual(reloadedBlur.value as? String, blurValue)
        let reloadedDim = app.sliders["chat-background-dim"]
        if !reloadedDim.isHittable { app.swipeUp() }
        XCTAssertEqual(reloadedDim.value as? String, dimValue)
        app.swipeDown()
        let crop = app.buttons["chat-background-crop"]
        if !crop.isHittable { app.swipeDown() }
        crop.tap()
        let preview = app.descendants(matching: .any).matching(identifier: "chat-wallpaper-crop-preview").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.pinch(withScale: 1.5, velocity: 1)
        preview.swipeLeft()
        snapshot(app, "wallpaper-crop")
        app.buttons["chat-wallpaper-save"].tap()
        XCTAssertTrue(app.switches["chat-lockscreen-glass"].waitForExistence(timeout: 5))
        app.buttons["返回聊天设置"].tap()
        app.buttons["关闭聊天设置"].tap()
        let input = app.textFields["chat-composer"]
        input.tap()
        input.typeText("preview")
        snapshot(app, "wallpaper-white-composer-keyboard")
        XCTAssertTrue(app.staticTexts["这是最新一条回复。"].exists)
    }
}
