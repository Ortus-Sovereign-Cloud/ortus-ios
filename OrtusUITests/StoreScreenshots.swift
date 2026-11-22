import XCTest

/// The App Store screenshots, against an Ortus filled with the sample
/// organisation (workflow `screenshots`, which passes ORTUS_SERVER and a
/// phone sign-in code for its owner as ORTUS_SCREENSHOT_CODE). Skipped
/// everywhere else.
final class StoreScreenshots: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func shot(_ app: XCUIApplication, _ name: String) {
        // Let lists and avatars settle.
        sleep(2)
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func tap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func testStoreScreenshots() throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["ORTUS_SERVER"], !server.isEmpty, let code = env["ORTUS_SCREENSHOT_CODE"], !code.isEmpty else {
            throw XCTSkip("only in the screenshots workflow")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.textFields["code"].waitForExistence(timeout: 20))
        var open = URLComponents()
        open.scheme = "ortus"
        open.host = "signin"
        open.queryItems = [URLQueryItem(name: "server", value: server), URLQueryItem(name: "code", value: code)]
        XCUIDevice.shared.system.open(open.url!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Open"].waitForExistence(timeout: 5) { springboard.buttons["Open"].tap() }
        XCTAssertTrue(app.buttons["makeKey"].waitForExistence(timeout: 30))
        app.buttons["makeKey"].tap()
        XCTAssertTrue(app.tabBars.buttons["Mail"].waitForExistence(timeout: 30))

        // 1. Mail: the inbox, then a thread.
        app.tabBars.buttons["Mail"].tap()
        let thread = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Gauge readings'")).firstMatch
        XCTAssertTrue(thread.waitForExistence(timeout: 20))
        shot(app, "1-mail")
        thread.tap()
        XCTAssertTrue(app.textFields["reply"].waitForExistence(timeout: 10))
        shot(app, "2-thread")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 2. Chat: the channels, then one.
        app.tabBars.buttons["Chat"].tap()
        let channel = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'flood-response'")).firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 20))
        shot(app, "3-chat")
        channel.tap()
        XCTAssertTrue(app.textFields["message"].waitForExistence(timeout: 10))
        shot(app, "4-channel")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 3. Calendar: the week.
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Readiness review' OR label CONTAINS 'Sandbag move' OR label CONTAINS 'Town hall'")).firstMatch.waitForExistence(timeout: 20))
        shot(app, "5-calendar")

        // 4. Files.
        app.tabBars.buttons["Files"].tap()
        shot(app, "6-files")
    }
}
