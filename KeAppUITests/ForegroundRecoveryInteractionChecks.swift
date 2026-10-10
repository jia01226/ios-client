import XCTest

/// This uses the real send task and scene lifecycle, with an isolated server transport.
enum ForegroundRecoveryInteractionChecks {
    static func verify(in testCase: XCTestCase) {
        testCase.continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-foreground-recovery", "-app.skin", "day"]
        let monitor = testCase.addUIInterruptionMonitor(withDescription: "Existing system permissions") { alert in
            for title in ["Don’t Allow", "Don't Allow", "不允许", "稍后"] {
                if alert.buttons[title].exists { alert.buttons[title].tap(); return true }
            }
            return false
        }
        defer { testCase.removeUIInterruptionMonitor(monitor); app.terminate() }
        app.launch()
        let composer = app.textFields["chat-composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap() // handles the pre-existing motion permission prompt if shown
        composer.tap()
        composer.typeText("切回来看看")
        app.buttons["send-message"].tap()
        XCTAssertTrue(app.staticTexts["正在写这一句…"].waitForExistence(timeout: 5))
        capture("foreground-01-stream-before-background", in: testCase)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3) // server fixture is done after 2s, SSE remains frozen
        app.activate()
        XCTAssertTrue(app.staticTexts["我已经回好了，你回来就能看见。"].waitForExistence(timeout: 2))
        let timing = app.staticTexts["foreground-recovery-seconds"]
        XCTAssertTrue(timing.waitForExistence(timeout: 2))
        let seconds = Double(timing.label) ?? .infinity
        XCTAssertLessThan(seconds, 2, "Measured inside App from active entry to completed reply appearance")
        let metric = XCTAttachment(string: "Foreground entry to completed reply appearance: \(seconds) seconds. Local server fixture; real APNs/network not measured.")
        metric.name = "foreground-recovery-timing"; metric.lifetime = .keepAlways; testCase.add(metric)
        let header = app.descendants(matching: .any)["chat-header-test1"]
        XCTAssertTrue(header.label.contains("在线"), "Completed recovery must leave the sending state")
        XCTAssertFalse(app.staticTexts["正在写这一句…"].exists)
        XCTAssertFalse(app.staticTexts["回复中断"].exists)
        XCTAssertFalse(app.staticTexts["这句没有发稳。内容留在这里，网络恢复后可以再发。"].exists)
        capture("foreground-02-recovered-within-two-seconds", in: testCase)
    }
    private static func capture(_ name: String, in testCase: XCTestCase) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; testCase.add(shot)
    }
}
