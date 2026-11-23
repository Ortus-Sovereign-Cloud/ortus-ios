import XCTest

/// The App Store screenshots, against an Ortus filled with the sample
/// organisation (workflow `screenshots`, which passes ORTUS_SERVER and the
/// owner's session as ORTUS_SCREENSHOT_SESSION). Skipped
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
        guard let server = env["ORTUS_SERVER"], !server.isEmpty, let session = env["ORTUS_SCREENSHOT_SESSION"], !session.isEmpty else {
            throw XCTSkip("only in the screenshots workflow")
        }
        // A phone sign-in code from the owner's session, made now (codes
        // last five minutes).
        var request = URLRequest(url: URL(string: server + "/api/v1/me/phone-link")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ortus", forHTTPHeaderField: "X-Requested-With")
        request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        let done = DispatchSemaphore(value: 0)
        var body = Data()
        URLSession.shared.dataTask(with: request) { data, _, _ in body = data ?? Data(); done.signal() }.resume()
        done.wait()
        struct Made: Decodable { let link: String }
        let code = String(try JSONDecoder().decode(Made.self, from: body).link.split(separator: "p=").last ?? "")
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
        // The link names its installation; the person says yes.
        XCTAssertTrue(app.buttons["confirmLink"].waitForExistence(timeout: 20), "the link's installation to confirm")
        app.buttons["confirmLink"].tap()
        XCTAssertTrue(app.buttons["makeKey"].waitForExistence(timeout: 30))
        app.buttons["makeKey"].tap()
        XCTAssertTrue(app.tabBars.buttons["Mail"].waitForExistence(timeout: 30))

        // 1. Mail: the inbox, then a thread.
        app.tabBars.buttons["Mail"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Radio check'")).firstMatch.waitForExistence(timeout: 20), "the inbox")
        shot(app, "1-mail")
        // A conversation (three messages), not a calendar invitation: the
        // week's oldest, further down the list.
        let thread = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Sandbag stock'")).firstMatch
        for _ in 0..<8 where !thread.exists {
            app.swipeUp()
        }
        XCTAssertTrue(thread.waitForExistence(timeout: 5), "the Sandbag stock thread")
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
    }
}
